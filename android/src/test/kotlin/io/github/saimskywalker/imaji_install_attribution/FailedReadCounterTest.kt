package io.github.saimskywalker.imaji_install_attribution

import org.junit.Assert.assertEquals
import org.junit.Test
import java.io.File
import java.nio.file.Files

class FailedReadCounterTest {
    @Test
    fun countsSurviveANewInstanceAndClearResets() {
        val dir = Files.createTempDirectory("failures").toFile()
        val counter = FailedReadCounter(dir)
        assertEquals(0, counter.count())
        assertEquals(1, counter.increment())
        assertEquals(2, counter.increment())
        // A new process reads the same file.
        assertEquals(2, FailedReadCounter(dir).count())
        assertEquals(3, FailedReadCounter(dir).increment())
        counter.clear()
        assertEquals(0, FailedReadCounter(dir).count())
        dir.deleteRecursively()
    }

    @Test
    fun anUnreadableCountStartsAgainFromZero() {
        val dir = Files.createTempDirectory("failures").toFile()
        File(dir, "imaji_install_attribution.failed_reads").writeText("x")
        assertEquals(0, FailedReadCounter(dir).count())
        assertEquals(1, FailedReadCounter(dir).increment())
        dir.deleteRecursively()
    }
}
