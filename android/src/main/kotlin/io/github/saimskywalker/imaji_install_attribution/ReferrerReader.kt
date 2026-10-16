package io.github.saimskywalker.imaji_install_attribution

import com.android.installreferrer.api.InstallReferrerClient.InstallReferrerResponse
import java.util.concurrent.Executor
import java.util.concurrent.atomic.AtomicBoolean

/** Posts work to the platform (main) thread. */
internal interface MainThread {
    fun post(block: () -> Unit)

    /** Runs [block] after [delayMs]; the returned handle cancels it. */
    fun postDelayed(delayMs: Long, block: () -> Unit): Cancellable
}

internal fun interface Cancellable {
    fun cancel()
}

/**
 * One read of the Play Install Referrer, with the guarantees the Dart API
 * promises:
 *
 * - Every Binder call — the Play Store presence check
 *   (`PackageManager.getPackageInfo`) and the blocking `getInstallReferrer()`
 *   — runs on [worker], never on the platform thread, so a slow Play Store
 *   or package manager cannot freeze the UI.
 * - Every read ends after at most `timeoutMs`, as `timeout`.
 * - A `SERVICE_DISCONNECTED` (at setup, or a lost connection before the read
 *   started) gets exactly one reconnect.
 * - The callback runs exactly once, on the main thread, and nothing thrown
 *   by the library escapes.
 */
internal class ReferrerReader(
    private val newClient: () -> ReferrerClientPort,
    private val isPlayStoreInstalled: () -> Boolean,
    private val worker: Executor,
    private val main: MainThread,
) {
    fun read(timeoutMs: Long, onDone: (ReferrerOutcome) -> Unit) {
        Session(timeoutMs, onDone).start()
    }

    private inner class Session(
        private val timeoutMs: Long,
        private val onDone: (ReferrerOutcome) -> Unit,
    ) {
        // All fields below are only touched on the main thread.
        private val finished = AtomicBoolean(false)
        private var client: ReferrerClientPort? = null
        private var reconnectsLeft = 1
        private var readInFlight = false
        private var timeoutHandle: Cancellable? = null

        fun start() {
            timeoutHandle = main.postDelayed(timeoutMs) {
                finish(
                    ReferrerOutcome.Unavailable(
                        Reason.TIMEOUT,
                        "No answer from the Play Store referrer service within ${timeoutMs}ms.",
                    ),
                )
            }
            try {
                worker.execute {
                    val playStorePresent = try {
                        isPlayStoreInstalled()
                    } catch (_: Throwable) {
                        true // Unknown: let the bind decide.
                    }
                    main.post { onPlayStoreChecked(playStorePresent) }
                }
            } catch (error: Throwable) {
                // RejectedExecutionException: the plugin was detached.
                finish(ReferrerMapping.fromThrowable(error))
            }
        }

        private fun onPlayStoreChecked(present: Boolean) {
            if (finished.get()) return
            if (!present) {
                finish(
                    ReferrerOutcome.Unavailable(
                        Reason.PLAY_STORE_MISSING,
                        "The Google Play Store is not installed on this device.",
                    ),
                )
                return
            }
            connect()
        }

        private fun connect() {
            val next = try {
                newClient()
            } catch (error: Throwable) {
                finish(ReferrerMapping.fromThrowable(error))
                return
            }
            client = next
            try {
                next.startConnection(object : ReferrerClientPort.Listener {
                    override fun onSetupFinished(responseCode: Int) = onSetup(next, responseCode)

                    override fun onDisconnected() = onLost(next)
                })
            } catch (error: Throwable) {
                finish(ReferrerMapping.fromThrowable(error))
            }
        }

        private fun onSetup(from: ReferrerClientPort, code: Int) {
            if (finished.get() || from !== client) return
            if (code == InstallReferrerResponse.OK) {
                readInFlight = true
                try {
                    worker.execute {
                        val outcome = ReferrerMapping.readDetails { from.details() }
                        main.post {
                            readInFlight = false
                            finish(outcome)
                        }
                    }
                } catch (error: Throwable) {
                    // RejectedExecutionException: the plugin was detached.
                    readInFlight = false
                    finish(ReferrerMapping.fromThrowable(error))
                }
                return
            }
            if (code == InstallReferrerResponse.SERVICE_DISCONNECTED && reconnect()) return
            finish(
                ReferrerMapping.fromResponseCode(code)
                    ?: ReferrerOutcome.Unavailable(Reason.INTERNAL_ERROR, "Unexpected OK."),
            )
        }

        private fun onLost(from: ReferrerClientPort) {
            // While the read is in flight, the Binder call itself reports the
            // loss (DeadObjectException), which is the more precise reason.
            if (finished.get() || from !== client || readInFlight) return
            if (reconnect()) return
            finish(
                ReferrerOutcome.Unavailable(
                    Reason.SERVICE_DISCONNECTED,
                    "The Play Store referrer service disconnected twice.",
                ),
            )
        }

        private fun reconnect(): Boolean {
            if (reconnectsLeft <= 0) return false
            reconnectsLeft--
            endQuietly(client)
            client = null
            connect()
            return true
        }

        private fun finish(outcome: ReferrerOutcome) {
            if (!finished.compareAndSet(false, true)) return
            timeoutHandle?.cancel()
            timeoutHandle = null
            val last = client
            client = null
            endQuietly(last)
            onDone(outcome)
        }

        private fun endQuietly(target: ReferrerClientPort?) {
            try {
                target?.endConnection()
            } catch (_: Throwable) {
                // Ending an already-dead connection is not worth reporting.
            }
        }
    }
}
