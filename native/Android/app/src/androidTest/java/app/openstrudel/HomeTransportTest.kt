package app.openstrudel

import androidx.test.ext.junit.runners.AndroidJUnit4
import java.security.MessageDigest
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.withContext
import okhttp3.mockwebserver.MockResponse
import okhttp3.mockwebserver.MockWebServer
import okhttp3.tls.HandshakeCertificates
import okhttp3.tls.HeldCertificate
import org.junit.Assert.assertEquals
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class HomeTransportTest {
    @Test
    fun readsMultipleTlsRecordsWithoutStalling() = runBlocking {
        val certificate = HeldCertificate.Builder().commonName("QA").build()
        val tls = HandshakeCertificates.Builder().heldCertificate(certificate).build()
        val server =
            MockWebServer().apply {
                useHttps(tls.sslSocketFactory(), false)
                start()
            }
        val pin =
            MessageDigest.getInstance("SHA-256")
                .digest(certificate.certificate.encoded)
                .joinToString("") { "%02x".format(it.toInt() and 255) }
        val api =
            HomeApi(
                Connection(
                    "qa",
                    server.url("/").toString().removeSuffix("/"),
                    "a".repeat(64),
                    pin,
                    "TLS fixture",
                )
            )
        try {
            repeat(10) {
                server.enqueue(MockResponse().setBody(json("text" to "Я".repeat(40000)).toString()))
                val result = withContext(Dispatchers.IO) { api.call("/health") }
                assertEquals(40000, result.json.getString("text").length)
            }
        } finally {
            api.close()
            server.shutdown()
        }
    }
}
