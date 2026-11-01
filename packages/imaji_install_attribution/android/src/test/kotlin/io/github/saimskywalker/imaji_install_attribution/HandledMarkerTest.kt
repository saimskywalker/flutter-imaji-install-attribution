package io.github.saimskywalker.imaji_install_attribution

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File
import java.nio.file.Files

class HandledMarkerTest {
    @Test
    fun markAndClearRoundTrip() {
        val dir = Files.createTempDirectory("marker").toFile()
        val marker = HandledMarker(dir)
        assertFalse(marker.isHandled())
        marker.markHandled()
        assertTrue(marker.isHandled())
        assertTrue(HandledMarker(dir).isHandled())
        marker.clear()
        assertFalse(marker.isHandled())
        dir.deleteRecursively()
    }

    @Test
    fun markingTwiceIsIdempotent() {
        val dir = Files.createTempDirectory("marker").toFile()
        val marker = HandledMarker(dir)
        marker.markHandled()
        val file = File(dir, "imaji_install_attribution.handled")
        val first = file.readText()
        Thread.sleep(5)
        marker.markHandled()
        assertTrue(marker.isHandled())
        assertEquals(first, file.readText())
        dir.deleteRecursively()
    }
}
