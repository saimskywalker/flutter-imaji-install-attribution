package io.github.saimskywalker.imaji_install_attribution

import android.os.DeadObjectException
import android.os.RemoteException
import com.android.installreferrer.api.InstallReferrerClient.InstallReferrerResponse

/**
 * Reason codes sent to Dart. Each one is the `name` of a value of the Dart
 * `UnavailableReason` enum, so the two sides must change together.
 */
internal object Reason {
    const val TIMEOUT = "timeout"
    const val PLAY_STORE_MISSING = "playStoreMissing"
    const val FEATURE_NOT_SUPPORTED = "featureNotSupported"
    const val SERVICE_UNAVAILABLE = "serviceUnavailable"
    const val SERVICE_DISCONNECTED = "serviceDisconnected"
    const val DEAD_SERVICE = "deadService"
    const val PERMISSION_ERROR = "permissionError"
    const val DEVELOPER_ERROR = "developerError"
    const val NULL_DETAILS = "nullDetails"
    const val UNKNOWN_RESPONSE = "unknownResponse"
    const val INTERNAL_ERROR = "internalError"
}

/** The values read off a `ReferrerDetails`, copied out while it was safe to. */
internal data class RawReferrerDetails(
    val referrer: String?,
    val clickSeconds: Long,
    val installBeginSeconds: Long,
    val clickServerSeconds: Long,
    val installBeginServerSeconds: Long,
    val installVersion: String?,
    val instantExperienceLaunched: Boolean,
)

/** What one read of the Play Install Referrer ended in. */
internal sealed class ReferrerOutcome {
    abstract fun toMap(): Map<String, Any?>

    data class Details(val details: RawReferrerDetails) : ReferrerOutcome() {
        override fun toMap(): Map<String, Any?> = mapOf(
            "status" to "referrer",
            "referrer" to details.referrer,
            "clickSeconds" to details.clickSeconds,
            "installBeginSeconds" to details.installBeginSeconds,
            "clickServerSeconds" to details.clickServerSeconds,
            "installBeginServerSeconds" to details.installBeginServerSeconds,
            "installVersion" to details.installVersion,
            "instantExperienceLaunched" to details.instantExperienceLaunched,
        )
    }

    data class Unavailable(val reason: String, val message: String?) : ReferrerOutcome() {
        override fun toMap(): Map<String, Any?> = mapOf(
            "status" to "unavailable",
            "reason" to reason,
            "message" to message,
        )
    }
}

/**
 * Pure mapping from what the Install Referrer library reports to a
 * [ReferrerOutcome]. Kept free of Android framework state so every branch is
 * unit-testable on the JVM.
 */
internal object ReferrerMapping {
    /**
     * Maps a non-OK `onInstallReferrerSetupFinished` response code. Returns
     * null for [InstallReferrerResponse.OK], which is not a failure.
     */
    fun fromResponseCode(code: Int): ReferrerOutcome.Unavailable? = when (code) {
        InstallReferrerResponse.OK -> null
        InstallReferrerResponse.FEATURE_NOT_SUPPORTED -> ReferrerOutcome.Unavailable(
            Reason.FEATURE_NOT_SUPPORTED,
            "The installed Play Store app does not offer the Install Referrer API.",
        )
        InstallReferrerResponse.SERVICE_UNAVAILABLE -> ReferrerOutcome.Unavailable(
            Reason.SERVICE_UNAVAILABLE,
            "The Play Store referrer service is not available right now.",
        )
        InstallReferrerResponse.SERVICE_DISCONNECTED -> ReferrerOutcome.Unavailable(
            Reason.SERVICE_DISCONNECTED,
            "The Play Store referrer service disconnected.",
        )
        InstallReferrerResponse.DEVELOPER_ERROR -> ReferrerOutcome.Unavailable(
            Reason.DEVELOPER_ERROR,
            "The Install Referrer library reported a developer error.",
        )
        InstallReferrerResponse.PERMISSION_ERROR -> ReferrerOutcome.Unavailable(
            Reason.PERMISSION_ERROR,
            "The app is not allowed to bind to the Play Store referrer service. " +
                "Check that the merged manifest still has " +
                "com.google.android.finsky.permission.BIND_GET_INSTALL_REFERRER_SERVICE.",
        )
        else -> ReferrerOutcome.Unavailable(
            Reason.UNKNOWN_RESPONSE,
            "Unknown Install Referrer response code $code.",
        )
    }

    /** Maps anything thrown while binding to, or reading from, the service. */
    fun fromThrowable(error: Throwable): ReferrerOutcome.Unavailable = when (error) {
        // Play answered OK but its ReferrerDetails wraps a null Bundle; every
        // getter then throws inside BaseBundle.getString.
        is NullPointerException -> ReferrerOutcome.Unavailable(
            Reason.NULL_DETAILS,
            "Play returned referrer details without a details bundle.",
        )
        // The Play Store process died while the Binder call was in flight.
        is DeadObjectException -> ReferrerOutcome.Unavailable(
            Reason.DEAD_SERVICE,
            "The Play Store referrer service died during the read.",
        )
        is RemoteException -> ReferrerOutcome.Unavailable(
            Reason.SERVICE_UNAVAILABLE,
            "The Play Store referrer service failed: ${error.javaClass.simpleName}.",
        )
        is SecurityException -> ReferrerOutcome.Unavailable(
            Reason.PERMISSION_ERROR,
            "Binding to the Play Store referrer service was refused.",
        )
        else -> ReferrerOutcome.Unavailable(
            Reason.INTERNAL_ERROR,
            "Reading the install referrer failed: ${error.javaClass.name}.",
        )
    }

    /**
     * Runs the blocking read and turns every possible failure into an
     * outcome. Never throws.
     */
    fun readDetails(read: () -> RawReferrerDetails?): ReferrerOutcome = try {
        val details = read()
        if (details == null) {
            ReferrerOutcome.Unavailable(Reason.NULL_DETAILS, "Play returned no referrer details.")
        } else {
            ReferrerOutcome.Details(details)
        }
    } catch (error: Throwable) {
        fromThrowable(error)
    }
}
