package io.github.saimskywalker.imaji_install_attribution

import android.content.Context
import com.android.installreferrer.api.InstallReferrerClient
import com.android.installreferrer.api.InstallReferrerStateListener

/**
 * The slice of `InstallReferrerClient` the reader uses. The seam exists so
 * unit tests can drive every connection branch without a Play Store.
 */
internal interface ReferrerClientPort {
    interface Listener {
        /** Delivered on the main looper by the real client. */
        fun onSetupFinished(responseCode: Int)

        /** The service connection was lost after a successful setup. */
        fun onDisconnected()
    }

    fun startConnection(listener: Listener)

    /** Blocking Binder call. Must never run on the platform thread. */
    fun details(): RawReferrerDetails?

    fun endConnection()
}

/** [ReferrerClientPort] backed by the Play Install Referrer library. */
internal class PlayReferrerClient(context: Context) : ReferrerClientPort {
    private val client: InstallReferrerClient =
        InstallReferrerClient.newBuilder(context.applicationContext).build()

    override fun startConnection(listener: ReferrerClientPort.Listener) {
        client.startConnection(object : InstallReferrerStateListener {
            override fun onInstallReferrerSetupFinished(responseCode: Int) {
                listener.onSetupFinished(responseCode)
            }

            override fun onInstallReferrerServiceDisconnected() {
                listener.onDisconnected()
            }
        })
    }

    override fun details(): RawReferrerDetails? {
        val details = client.installReferrer ?: return null
        // Every getter reads the same internal Bundle; when Play hands back a
        // null one, the first getter throws NullPointerException, which the
        // caller maps to `nullDetails`.
        return RawReferrerDetails(
            referrer = details.installReferrer,
            clickSeconds = details.referrerClickTimestampSeconds,
            installBeginSeconds = details.installBeginTimestampSeconds,
            clickServerSeconds = details.referrerClickTimestampServerSeconds,
            installBeginServerSeconds = details.installBeginTimestampServerSeconds,
            installVersion = details.installVersion,
            instantExperienceLaunched = details.googlePlayInstantParam,
        )
    }

    override fun endConnection() {
        client.endConnection()
    }
}
