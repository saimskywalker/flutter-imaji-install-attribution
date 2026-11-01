package io.github.saimskywalker.imaji_install_attribution

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test
import java.io.File
import java.nio.file.Files

class InstallFactsTest {
    private fun tempDir(): File = Files.createTempDirectory("facts").toFile()

    @Test
    fun firstSeenIsRecordedOnceAndNeverMoves() {
        val dir = tempDir()
        val record = FirstSeenRecord(dir)
        assertNull(record.read())
        assertEquals(1_000L, record.getOrCreate(1_000L))
        assertEquals(1_000L, record.getOrCreate(9_000L))
        assertEquals(1_000L, FirstSeenRecord(dir).read())
        dir.deleteRecursively()
    }

    @Test
    fun anUnreadableRecordIsReplaced() {
        val dir = tempDir()
        File(dir, "imaji_install_attribution.first_seen").writeText("garbage")
        val record = FirstSeenRecord(dir)
        assertNull(record.read())
        assertEquals(5_000L, record.getOrCreate(5_000L))
        assertEquals(5_000L, record.read())
        dir.deleteRecursively()
    }

    @Test
    fun clearingTheHandledMarkerKeepsTheFirstSeenRecord() {
        val dir = tempDir()
        FirstSeenRecord(dir).getOrCreate(1_000L)
        val marker = HandledMarker(dir)
        marker.markHandled()
        marker.clear()
        assertEquals(1_000L, FirstSeenRecord(dir).read())
        dir.deleteRecursively()
    }

    @Test
    fun replyCarriesTheKeysDartReads() {
        val reply = InstallFactsReader.toMap(1L, 2L, 3L, "1.0.0")
        assertEquals(
            mapOf(
                "firstInstallMs" to 1L,
                "lastUpdateMs" to 2L,
                "pluginFirstSeenMs" to 3L,
                "versionName" to "1.0.0",
            ),
            reply,
        )
    }
}
