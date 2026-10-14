package io.github.saimskywalker.imaji_install_attribution

import android.os.DeadObjectException
import com.android.installreferrer.api.InstallReferrerClient.InstallReferrerResponse
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import java.util.concurrent.Executor

class ReferrerReaderTest {
    private val details = RawReferrerDetails(
        referrer = "utm_source=newsletter",
        clickSeconds = 1,
        installBeginSeconds = 2,
        clickServerSeconds = 3,
        installBeginServerSeconds = 4,
        installVersion = null,
        instantExperienceLaunched = false,
    )

    /** A scripted client: each startConnection answers per [onStart]. */
    private class FakeClient(
        val onStart: (ReferrerClientPort.Listener) -> Unit,
        val read: () -> RawReferrerDetails?,
    ) : ReferrerClientPort {
        var readThread: Thread? = null
        var ended = 0

        override fun startConnection(listener: ReferrerClientPort.Listener) = onStart(listener)

        override fun details(): RawReferrerDetails? {
            readThread = Thread.currentThread()
            return read()
        }

        override fun endConnection() {
            ended++
        }
    }

    /** Main thread stand-in: posts run inline, delayed work runs on [advance]. */
    private class FakeMain : MainThread {
        val pending = mutableListOf<Pair<Long, () -> Unit>>()
        var now = 0L

        override fun post(block: () -> Unit) = block()

        override fun postDelayed(delayMs: Long, block: () -> Unit): Cancellable {
            val entry = (now + delayMs) to block
            pending += entry
            return Cancellable { pending.remove(entry) }
        }

        fun advance(ms: Long) {
            now += ms
            val due = pending.filter { it.first <= now }
            pending.removeAll(due)
            due.forEach { it.second() }
        }
    }

    /** Records which thread ran the work; runs it on a separate thread. */
    private class ThreadExecutor : Executor {
        override fun execute(command: Runnable) {
            val t = Thread(command)
            t.start()
            t.join()
        }
    }

    private val inline = Executor { it.run() }

    private fun run(
        clients: List<FakeClient>,
        playStore: Boolean = true,
        worker: Executor = inline,
        main: FakeMain = FakeMain(),
        timeoutMs: Long = 10_000,
        afterStart: (FakeMain) -> Unit = {},
    ): List<ReferrerOutcome> {
        val queue = ArrayDeque(clients)
        val outcomes = mutableListOf<ReferrerOutcome>()
        val reader = ReferrerReader(
            newClient = { queue.removeFirst() },
            isPlayStoreInstalled = { playStore },
            worker = worker,
            main = main,
        )
        reader.read(timeoutMs) { outcomes += it }
        afterStart(main)
        return outcomes
    }

    private fun reason(outcome: ReferrerOutcome) = (outcome as ReferrerOutcome.Unavailable).reason

    @Test
    fun okReadsDetailsOffThePlatformThread() {
        val client = FakeClient({ it.onSetupFinished(InstallReferrerResponse.OK) }, { details })
        val outcomes = run(listOf(client), worker = ThreadExecutor())
        assertEquals(listOf<ReferrerOutcome>(ReferrerOutcome.Details(details)), outcomes)
        assertTrue(client.readThread !== Thread.currentThread())
        assertEquals(1, client.ended)
    }

    @Test
    fun missingPlayStoreNeverBinds() {
        val outcomes = run(emptyList(), playStore = false)
        assertEquals(Reason.PLAY_STORE_MISSING, reason(outcomes.single()))
    }

    @Test
    fun timeoutEndsTheConnectionAndLateResultsAreIgnored() {
        var listener: ReferrerClientPort.Listener? = null
        val client = FakeClient({ listener = it }, { details })
        val main = FakeMain()
        val outcomes = run(listOf(client), main = main, timeoutMs = 500) { it.advance(500) }
        assertEquals(Reason.TIMEOUT, reason(outcomes.single()))
        assertEquals(1, client.ended)
        // The service answers after the deadline: nothing else is delivered.
        listener!!.onSetupFinished(InstallReferrerResponse.OK)
        assertEquals(1, outcomes.size)
    }

    @Test
    fun setupDisconnectGetsExactlyOneReconnect() {
        val first = FakeClient({ it.onSetupFinished(InstallReferrerResponse.SERVICE_DISCONNECTED) }, { details })
        val second = FakeClient({ it.onSetupFinished(InstallReferrerResponse.OK) }, { details })
        val outcomes = run(listOf(first, second))
        assertEquals(listOf<ReferrerOutcome>(ReferrerOutcome.Details(details)), outcomes)
        assertEquals(1, first.ended)
    }

    @Test
    fun secondDisconnectIsReported() {
        val clients = List(2) {
            FakeClient({ it.onSetupFinished(InstallReferrerResponse.SERVICE_DISCONNECTED) }, { details })
        }
        val outcomes = run(clients)
        assertEquals(Reason.SERVICE_DISCONNECTED, reason(outcomes.single()))
    }

    @Test
    fun lostConnectionBeforeSetupReconnectsOnce() {
        val first = FakeClient({ it.onDisconnected() }, { details })
        val second = FakeClient({ it.onDisconnected() }, { details })
        val outcomes = run(listOf(first, second))
        assertEquals(Reason.SERVICE_DISCONNECTED, reason(outcomes.single()))
    }

    @Test
    fun deadObjectDuringReadIsTyped() {
        val client = FakeClient(
            { it.onSetupFinished(InstallReferrerResponse.OK) },
            { throw DeadObjectException() },
        )
        assertEquals(Reason.DEAD_SERVICE, reason(run(listOf(client)).single()))
    }

    @Test
    fun nullBundleDuringReadIsTyped() {
        val client = FakeClient(
            { it.onSetupFinished(InstallReferrerResponse.OK) },
            { throw NullPointerException("null bundle") },
        )
        assertEquals(Reason.NULL_DETAILS, reason(run(listOf(client)).single()))
    }

    @Test
    fun setupErrorsAreTyped() {
        val table = mapOf(
            InstallReferrerResponse.FEATURE_NOT_SUPPORTED to Reason.FEATURE_NOT_SUPPORTED,
            InstallReferrerResponse.SERVICE_UNAVAILABLE to Reason.SERVICE_UNAVAILABLE,
            InstallReferrerResponse.DEVELOPER_ERROR to Reason.DEVELOPER_ERROR,
            InstallReferrerResponse.PERMISSION_ERROR to Reason.PERMISSION_ERROR,
        )
        for ((code, expected) in table) {
            val client = FakeClient({ it.onSetupFinished(code) }, { details })
            assertEquals("code $code", expected, reason(run(listOf(client)).single()))
        }
    }

    @Test
    fun bindThatThrowsIsTyped() {
        val client = FakeClient({ throw SecurityException("not allowed to bind") }, { details })
        assertEquals(Reason.PERMISSION_ERROR, reason(run(listOf(client)).single()))
    }

    @Test
    fun rejectedWorkerIsTypedNotThrown() {
        val client = FakeClient({ it.onSetupFinished(InstallReferrerResponse.OK) }, { details })
        val rejecting = Executor { throw java.util.concurrent.RejectedExecutionException() }
        assertEquals(Reason.INTERNAL_ERROR, reason(run(listOf(client), worker = rejecting).single()))
    }

    @Test
    fun timeoutIsCancelledOnSuccess() {
        val client = FakeClient({ it.onSetupFinished(InstallReferrerResponse.OK) }, { details })
        val main = FakeMain()
        val outcomes = run(listOf(client), main = main) { it.advance(60_000) }
        assertEquals(1, outcomes.size)
        assertTrue(main.pending.isEmpty())
    }
}
