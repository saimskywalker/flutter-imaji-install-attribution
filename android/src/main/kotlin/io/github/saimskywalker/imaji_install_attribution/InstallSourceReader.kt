package io.github.saimskywalker.imaji_install_attribution

import android.content.Context
import android.content.pm.PackageManager
import android.os.Build

/**
 * Which package installed this app. Raw package names only: the mapping to
 * a store (Play, Galaxy Store, side-load, restore, ...) lives in Dart so both
 * platforms share it and it is unit-testable without a device.
 */
internal object InstallSourceReader {
    fun read(context: Context): Map<String, Any?> {
        val packageManager = context.packageManager
        val packageName = context.packageName
        return try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                val info = packageManager.getInstallSourceInfo(packageName)
                mapOf(
                    "installerPackage" to info.installingPackageName,
                    "initiatingPackage" to info.initiatingPackageName,
                    "sdkInt" to Build.VERSION.SDK_INT,
                )
            } else {
                @Suppress("DEPRECATION")
                val installer = packageManager.getInstallerPackageName(packageName)
                mapOf(
                    "installerPackage" to installer,
                    "initiatingPackage" to null,
                    "sdkInt" to Build.VERSION.SDK_INT,
                )
            }
        } catch (error: PackageManager.NameNotFoundException) {
            failure(error)
        } catch (error: RuntimeException) {
            failure(error)
        }
    }

    /** True when the Play Store package is installed (enabled or not). */
    fun isPlayStoreInstalled(context: Context): Boolean = try {
        val packageManager = context.packageManager
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            packageManager.getPackageInfo(PLAY_STORE, PackageManager.PackageInfoFlags.of(0))
        } else {
            @Suppress("DEPRECATION")
            packageManager.getPackageInfo(PLAY_STORE, 0)
        }
        true
    } catch (_: PackageManager.NameNotFoundException) {
        false
    }

    private fun failure(error: Throwable): Map<String, Any?> = mapOf(
        "installerPackage" to null,
        "initiatingPackage" to null,
        "sdkInt" to Build.VERSION.SDK_INT,
        "error" to error.javaClass.name,
    )

    private const val PLAY_STORE = "com.android.vending"
}
