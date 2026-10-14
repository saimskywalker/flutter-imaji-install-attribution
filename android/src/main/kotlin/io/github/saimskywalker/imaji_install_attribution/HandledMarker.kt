package io.github.saimskywalker.imaji_install_attribution

import java.io.File

/**
 * The consume-once marker: one tiny file whose presence means "the app has
 * handled its install attribution".
 *
 * It lives in `noBackupFilesDir`, which Android Auto Backup never copies, so
 * a reinstall (or a restore onto a new phone) starts unhandled — the same
 * moment Play hands the app a fresh referrer.
 */
internal class HandledMarker(directory: File) {
    private val file = File(directory, FILE_NAME)

    fun isHandled(): Boolean = file.exists()

    fun markHandled() {
        file.parentFile?.mkdirs()
        file.writeText(System.currentTimeMillis().toString())
    }

    fun clear() {
        file.delete()
    }

    private companion object {
        const val FILE_NAME = "imaji_install_attribution.handled"
    }
}
