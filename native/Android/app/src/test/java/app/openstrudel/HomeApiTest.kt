package app.openstrudel

import java.security.MessageDigest
import java.util.Base64
import java.util.UUID
import kotlinx.coroutines.runBlocking
import okhttp3.mockwebserver.MockResponse
import okhttp3.mockwebserver.MockWebServer
import okhttp3.tls.HandshakeCertificates
import okhttp3.tls.HeldCertificate
import org.junit.After
import org.junit.Assert.*
import org.junit.Before
import org.junit.Test

class HomeApiTest {
    private lateinit var server: MockWebServer
    private lateinit var certificate: HeldCertificate
    private lateinit var api: HomeApi
    private val token = "a".repeat(64)

    private fun hash(bytes: ByteArray) =
        MessageDigest.getInstance("SHA-256").digest(bytes).joinToString("") {
            "%02x".format(it.toInt() and 255)
        }

    @Before
    fun setUp() {
        certificate = HeldCertificate.Builder().commonName("OpenStrudel Home").build()
        val tls = HandshakeCertificates.Builder().heldCertificate(certificate).build()
        server =
            MockWebServer().apply {
                useHttps(tls.sslSocketFactory(), false)
                start()
            }
        api =
            HomeApi(
                Connection(
                    "fixture",
                    server.url("/").toString().removeSuffix("/"),
                    token,
                    hash(certificate.certificate.encoded),
                    "QA",
                )
            )
    }

    @After
    fun tearDown() {
        api.close()
        server.shutdown()
    }

    @Test
    fun selfSignedHomeIsAcceptedOnlyByItsInvitationPin() = runBlocking {
        server.enqueue(MockResponse().setBody("{\"ok\":true}"))
        assertTrue(api.call("/health").json.getBoolean("ok"))
        assertEquals("Bearer $token", server.takeRequest().getHeader("Authorization"))
        val wrong = HomeApi(api.connection.copy(pin = "0".repeat(64)))
        try {
            assertTrue(runCatching { wrong.call("/health") }.isFailure)
        } finally {
            wrong.close()
        }
    }

    @Test
    fun publicKeyPinSurvivesCertificateRenewalWithoutTrustingAnotherKey() = runBlocking {
        val pinned =
            HomeApi(
                api.connection.copy(pin = "spki:" + hash(certificate.certificate.publicKey.encoded))
            )
        try {
            server.enqueue(MockResponse().setBody("{}"))
            assertEquals(200, pinned.call("/health").code)
        } finally {
            pinned.close()
        }
        val renewal =
            HeldCertificate.Builder()
                .keyPair(certificate.keyPair)
                .commonName("Renewed Home")
                .build()
        PinTrust("spki:" + hash(certificate.certificate.publicKey.encoded))
            .checkServerTrusted(arrayOf(renewal.certificate), null)
        assertTrue(
            runCatching {
                PinTrust(hash(certificate.certificate.encoded))
                    .checkServerTrusted(arrayOf(renewal.certificate), null)
            }
                .isFailure
        )
    }

    @Test
    fun redirectsNeverForwardCredentials() = runBlocking {
        MockWebServer().use { destination ->
            destination.start()
            server.enqueue(
                MockResponse()
                    .setResponseCode(302)
                    .setHeader("Location", destination.url("/steal"))
                    .setBody("{}")
            )
            assertTrue(runCatching { api.call("/health") }.exceptionOrNull() is HomeFailure)
            assertEquals(0, destination.requestCount)
        }
    }

    @Test
    fun pairingRetriesCarryTheSameNonceAndReadShortResponse() = runBlocking {
        val nonce = UUID.randomUUID().toString()
        repeat(2) {
            server.enqueue(MockResponse().setBody("{\"token\":\"$token\"}"))
            assertEquals(token, api.pair(nonce, "Samsung QA"))
            val r = server.takeRequest()
            assertEquals(nonce, r.getHeader("X-OpenStrudel-Pair-ID"))
            assertFalse(r.requestUrl!!.toString().contains(token))
        }
    }

    @Test
    fun etagAndIdempotencyFollowTheProtocol() = runBlocking {
        server.enqueue(MockResponse().setResponseCode(304))
        assertEquals("catalogue-4", api.call("/v1/profiles", etag = "catalogue-4").etag)
        assertEquals("catalogue-4", server.takeRequest().getHeader("If-None-Match"))
        val id = UUID.randomUUID().toString()
        repeat(2) {
            server.enqueue(MockResponse().setBody("{\"messageId\":\"m\"}"))
            api.call("/v1/messages?async=true", "POST", json("externalId" to id), id)
            assertEquals(id, server.takeRequest().getHeader("Idempotency-Key"))
        }
    }

    @Test
    fun relayedActionsWaitForTheActualServerResult() = runBlocking {
        server.enqueue(MockResponse().setResponseCode(202).setBody("{\"operationId\":\"op\"}"))
        val result =
            Base64.getEncoder().encodeToString("{\"profile\":{\"id\":\"employee\"}}".toByteArray())
        server.enqueue(
            MockResponse()
                .setBody(json("response" to json("status" to 201, "body" to result)).toString())
        )
        assertEquals(
            "employee",
            api.action("/v1/profiles").getJSONObject("profile").getString("id"),
        )
    }

    @Test
    fun closedPooledConnectionRecoversButAmbiguousWriteIsNotReplayed() = runBlocking {
        server.enqueue(MockResponse().setBody("{}"))
        api.call("/health")
        server.takeRequest()
        server.enqueue(
            MockResponse()
                .setSocketPolicy(okhttp3.mockwebserver.SocketPolicy.DISCONNECT_AFTER_REQUEST)
        )
        server.enqueue(MockResponse().setBody("{\"ok\":true}"))
        assertTrue(api.call("/health").json.getBoolean("ok"))
        assertEquals(3, server.requestCount)
        server.enqueue(
            MockResponse()
                .setSocketPolicy(okhttp3.mockwebserver.SocketPolicy.DISCONNECT_AFTER_REQUEST)
        )
        assertTrue(
            runCatching { api.call("/v1/profiles", "POST", json("name" to "single")) }.isFailure
        )
        assertEquals(4, server.requestCount)
    }

    @Test
    fun certificateExpiryFailsClosed() {
        val expired = HeldCertificate.Builder().validityInterval(1, 2).build()
        assertTrue(
            runCatching {
                PinTrust(hash(expired.certificate.encoded))
                    .checkServerTrusted(arrayOf(expired.certificate), null)
            }
                .isFailure
        )
    }
}
