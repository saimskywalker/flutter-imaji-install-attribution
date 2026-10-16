package io.github.saimskywalker.imaji_install_attribution

import android.content.Context
import android.os.Handler
import android.os.Looper
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors

/**
 * Flutter entry point. Every method answers with `success` — failures travel
 * as data (`status: unavailable`) so the Dart side never sees a
 * PlatformException from this plugin.
 */
class ImajiInstallAttributionPlugin : FlutterPlugin, MethodChannel.MethodCallHandler {
    private var channel: MethodChannel? = null
    private var context: Context? = null
    private var worker: ExecutorService? = null
    private var reader: ReferrerReader? = null

    /** Bumped on every attach/detach; replies from an older engine are dropped. */
    @Volatile
    private var generation = 0

    private val mainHandler = Handler(Looper.getMainLooper())

    private val mainThread = object : MainThread {
        override fun post(block: () -> Unit) {
            mainHandler.post(block)
        }

        override fun postDelayed(delayMs: Long, block: () -> Unit): Cancellable {
            val runnable = Runnable(block)
            mainHandler.postDelayed(runnable, delayMs)
            return Cancellable { mainHandler.removeCallbacks(runnable) }
        }
    }

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        generation++
        val appContext = binding.applicationContext
        context = appContext
        val executor = Executors.newSingleThreadExecutor { runnable ->
            Thread(runnable, "imaji-install-attribution").apply { isDaemon = true }
        }
        worker = executor
        // Record the plugin's first start on this install before anything
        // can ask for it. The executor is single-threaded, so a later
        // `installFacts` call always sees this write.
        try {
            executor.execute {
                try {
                    firstSeen(appContext).getOrCreate(System.currentTimeMillis())
                } catch (_: Throwable) {
                    // Retried by `installFacts`.
                }
            }
        } catch (_: Throwable) {
            // Executor already rejected: nothing to record.
        }
        reader = ReferrerReader(
            newClient = { PlayReferrerClient(appContext) },
            isPlayStoreInstalled = { InstallSourceReader.isPlayStoreInstalled(appContext) },
            worker = executor,
            main = mainThread,
        )
        channel = MethodChannel(binding.binaryMessenger, CHANNEL).also {
            it.setMethodCallHandler(this)
        }
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        generation++
        channel?.setMethodCallHandler(null)
        channel = null
        worker?.shutdownNow()
        worker = null
        reader = null
        context = null
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        val reply = guardedReply(result)
        try {
            when (call.method) {
                "read" -> read(call, reply)
                "installSource" -> withContext(reply) { InstallSourceReader.read(it) }
                "installFacts" -> withContext(reply) {
                    InstallFactsReader.read(it, firstSeen(it), System.currentTimeMillis())
                }
                "isHandled" -> withContext(reply) { marker(it).isHandled() }
                "markHandled" -> withContext(reply) { marker(it).markHandled(); true }
                "clearHandled" -> withContext(reply) { marker(it).clear(); true }
                else -> result.notImplemented()
            }
        } catch (error: Throwable) {
            reply(ReferrerMapping.fromThrowable(error).toMap())
        }
    }

    private fun read(call: MethodCall, reply: (Any?) -> Unit) {
        val active = reader
        if (active == null) {
            reply(ReferrerOutcome.Unavailable(Reason.INTERNAL_ERROR, "Plugin detached.").toMap())
            return
        }
        val timeoutMs = (call.argument<Number>("timeoutMs")?.toLong() ?: DEFAULT_TIMEOUT_MS)
            .coerceAtLeast(1L)
        active.read(timeoutMs) { outcome -> reply(outcome.toMap()) }
    }

    /** Runs small file / PackageManager work off the platform thread. */
    private fun withContext(reply: (Any?) -> Unit, work: (Context) -> Any?) {
        val ctx = context
        val executor = worker
        if (ctx == null || executor == null) {
            reply(null)
            return
        }
        try {
            executor.execute {
                val value = try {
                    work(ctx)
                } catch (_: Throwable) {
                    null
                }
                mainHandler.post { reply(value) }
            }
        } catch (_: Throwable) {
            reply(null)
        }
    }

    private fun marker(ctx: Context) = HandledMarker(ctx.noBackupFilesDir)

    private fun firstSeen(ctx: Context) = FirstSeenRecord(ctx.noBackupFilesDir)

    /** Replies at most once, on the main thread, and only to the same engine. */
    private fun guardedReply(result: MethodChannel.Result): (Any?) -> Unit {
        val callGeneration = generation
        var replied = false
        return { value ->
            if (!replied && callGeneration == generation) {
                replied = true
                try {
                    result.success(value)
                } catch (_: Throwable) {
                    // The engine went away between the check and the reply.
                }
            }
        }
    }

    private companion object {
        const val CHANNEL = "io.github.saimskywalker/imaji_install_attribution"
        const val DEFAULT_TIMEOUT_MS = 10_000L
    }
}
