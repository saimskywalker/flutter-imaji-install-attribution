package io.github.saimskywalker.imaji_install_attribution

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
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
}
