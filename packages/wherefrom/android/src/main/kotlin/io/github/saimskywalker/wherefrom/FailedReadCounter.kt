package io.github.saimskywalker.imaji_install_attribution

import java.io.File

/**
 * How many install-referrer reads have failed on this install: the retry
 * budget behind Dart's `claimOnce`. One tiny file next to the handled marker
 * in `noBackupFilesDir`, so it survives process death, starts over on a
 * reinstall, and is removed by `clearHandled`.
 */
internal class FailedReadCounter(directory: File) {
    private val file = File(directory, FILE_NAME)

    /** The stored count; 0 when absent or unreadable. */
    fun count(): Int = try {
        if (file.exists()) file.readText().trim().toIntOrNull()?.coerceAtLeast(0) ?: 0 else 0
    } catch (_: Exception) {
        0
    }

    /** Adds one failure and returns the new count. */
    fun increment(): Int {
        val next = count() + 1
        file.parentFile?.mkdirs()
        file.writeText(next.toString())
        return next
    }

    fun clear() {
        file.delete()
    }

    private companion object {
        const val FILE_NAME = "imaji_install_attribution.failed_reads"
    }
}
