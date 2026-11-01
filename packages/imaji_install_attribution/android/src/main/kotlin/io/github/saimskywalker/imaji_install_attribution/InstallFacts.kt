package io.github.saimskywalker.imaji_install_attribution

import android.content.Context
import android.content.pm.PackageInfo
import android.content.pm.PackageManager
import android.os.Build
import java.io.File

/**
 * The first time a version of the app containing this plugin started on this
 * install. One tiny file in `noBackupFilesDir`, written once and never
 * rewritten, so a reinstall or a restore onto a new device starts over.
 *
 * Dart compares it with `PackageInfo.lastUpdateTime` to tell an install
 * that existed before the plugin (the plugin arrived with an update) from a
 * fresh one.
 */
internal class FirstSeenRecord(directory: File) {
    private val file = File(directory, FILE_NAME)

    /** The recorded time, recording [now] first if there is none. */
    fun getOrCreate(now: Long): Long {
        read()?.let { return it }
        file.parentFile?.mkdirs()
        file.writeText(now.toString())
        return now
    }

    /** The recorded time, or null when absent or unreadable. */
    fun read(): Long? = try {
        if (file.exists()) file.readText().trim().toLongOrNull()?.takeIf { it > 0 } else null
    } catch (_: Exception) {
        null
    }

    private companion object {
        const val FILE_NAME = "imaji_install_attribution.first_seen"
    }
}

/** Reads the `installFacts` reply. Runs on the worker thread (Binder call). */
internal object InstallFactsReader {
    fun read(context: Context, record: FirstSeenRecord, now: Long): Map<String, Any?> {
        val firstSeen = try {
            record.getOrCreate(now)
        } catch (_: Exception) {
            null
        }
        val info = try {
            packageInfo(context)
        } catch (_: Exception) {
            null
        }
        return toMap(info?.firstInstallTime, info?.lastUpdateTime, firstSeen, info?.versionName)
    }

    fun toMap(
        firstInstallMs: Long?,
        lastUpdateMs: Long?,
        pluginFirstSeenMs: Long?,
        versionName: String?,
    ): Map<String, Any?> = mapOf(
        "firstInstallMs" to firstInstallMs,
        "lastUpdateMs" to lastUpdateMs,
        "pluginFirstSeenMs" to pluginFirstSeenMs,
        "versionName" to versionName,
    )

    private fun packageInfo(context: Context): PackageInfo {
        val packageManager = context.packageManager
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            packageManager.getPackageInfo(context.packageName, PackageManager.PackageInfoFlags.of(0))
        } else {
            @Suppress("DEPRECATION")
            packageManager.getPackageInfo(context.packageName, 0)
        }
    }
}
