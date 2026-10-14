package io.github.saimskywalker.imaji_install_attribution

import android.os.DeadObjectException
import android.os.RemoteException
import com.android.installreferrer.api.InstallReferrerClient.InstallReferrerResponse
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class ReferrerMappingTest {
    private fun reasonOf(outcome: ReferrerOutcome?): String =
        (outcome as ReferrerOutcome.Unavailable).reason

    @Test
    fun okIsNotAFailure() {
        assertNull(ReferrerMapping.fromResponseCode(InstallReferrerResponse.OK))
    }

    @Test
    fun everyResponseCodeHasItsOwnReason() {
        val table = mapOf(
            InstallReferrerResponse.FEATURE_NOT_SUPPORTED to Reason.FEATURE_NOT_SUPPORTED,
            InstallReferrerResponse.SERVICE_UNAVAILABLE to Reason.SERVICE_UNAVAILABLE,
            InstallReferrerResponse.SERVICE_DISCONNECTED to Reason.SERVICE_DISCONNECTED,
            InstallReferrerResponse.DEVELOPER_ERROR to Reason.DEVELOPER_ERROR,
            InstallReferrerResponse.PERMISSION_ERROR to Reason.PERMISSION_ERROR,
            42 to Reason.UNKNOWN_RESPONSE,
        )
        for ((code, reason) in table) {
            assertEquals("code $code", reason, reasonOf(ReferrerMapping.fromResponseCode(code)))
        }
    }

    @Test
    fun nullBundleNpeBecomesNullDetails() {
        val outcome = ReferrerMapping.readDetails {
            throw NullPointerException(
                "Attempt to invoke virtual method 'java.lang.String " +
                    "android.os.BaseBundle.getString(java.lang.String)' on a null object reference",
            )
        }
        assertEquals(Reason.NULL_DETAILS, reasonOf(outcome))
    }

    @Test
    fun nullDetailsObjectBecomesNullDetails() {
        assertEquals(Reason.NULL_DETAILS, reasonOf(ReferrerMapping.readDetails { null }))
    }

    @Test
    fun deadObjectBecomesDeadService() {
        val outcome = ReferrerMapping.readDetails { throw DeadObjectException() }
        assertEquals(Reason.DEAD_SERVICE, reasonOf(outcome))
    }

    @Test
    fun otherRemoteExceptionBecomesServiceUnavailable() {
        val outcome = ReferrerMapping.readDetails { throw RemoteException() }
        assertEquals(Reason.SERVICE_UNAVAILABLE, reasonOf(outcome))
    }

    @Test
    fun securityExceptionBecomesPermissionError() {
        val outcome = ReferrerMapping.readDetails { throw SecurityException("not allowed") }
        assertEquals(Reason.PERMISSION_ERROR, reasonOf(outcome))
    }

    @Test
    fun anythingElseBecomesInternalError() {
        val outcome = ReferrerMapping.readDetails { throw IllegalStateException("boom") }
        assertEquals(Reason.INTERNAL_ERROR, reasonOf(outcome))
    }

    @Test
    fun detailsAreCopiedThrough() {
        val raw = RawReferrerDetails(
            referrer = "utm_source=newsletter&utm_content=%2Fitems%2F42",
            clickSeconds = 10,
            installBeginSeconds = 20,
            clickServerSeconds = 11,
            installBeginServerSeconds = 21,
            installVersion = "1.0.0",
            instantExperienceLaunched = false,
        )
        val outcome = ReferrerMapping.readDetails { raw }
        assertTrue(outcome is ReferrerOutcome.Details)
        val map = outcome.toMap()
        assertEquals("referrer", map["status"])
        assertEquals(raw.referrer, map["referrer"])
        assertEquals(10L, map["clickSeconds"])
        assertEquals(21L, map["installBeginServerSeconds"])
    }
}
