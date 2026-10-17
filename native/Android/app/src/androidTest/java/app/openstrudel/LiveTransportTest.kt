package app.openstrudel

import android.content.Context
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import java.net.URL
import javax.net.ssl.HttpsURLConnection
import javax.net.ssl.SSLContext
import kotlinx.coroutines.runBlocking
import org.json.JSONObject
import org.junit.Assert.assertTrue
import org.junit.Assume.assumeTrue
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class LiveTransportTest {
    @Test
    fun compareNativeTlsReads() = runBlocking {
        assumeTrue(InstrumentationRegistry.getArguments().getString("liveRead") == "true")
        val state = SecureState(ApplicationProvider.getApplicationContext<Context>()).read()
        val route = InstrumentationRegistry.getArguments().getString("route")
        val homes =
            if (route == "usb")
                state.connections
                    .filter { it.name.contains("Mini") }
                    .take(1)
                    .map { it.copy(url = "https://127.0.0.1:17790") }
            else state.connections
        assertTrue("Pair a QA Home first", homes.isNotEmpty())
        for (home in homes) {
            val trust = PinTrust(home.pin)
            val tls = SSLContext.getInstance("TLS").apply { init(null, arrayOf(trust), null) }
            repeat(3) {
                val start = System.currentTimeMillis()
                val c = URL(home.url + "/v1/profiles").openConnection() as HttpsURLConnection
                c.sslSocketFactory = tls.socketFactory
                c.hostnameVerifier =
                    javax.net.ssl.HostnameVerifier { h, _ -> h == URL(home.url).host }
                c.connectTimeout = 10000
                c.readTimeout = 10000
                c.setRequestProperty("Authorization", "Bearer " + home.token)
                try {
                    val bytes = c.inputStream.use { it.readBytes() }
                    assertTrue(JSONObject(String(bytes)).has("profiles"))
                    android.util.Log.i(
                        "LiveRead",
                        "native ${URL(home.url).port} ${bytes.size} bytes ${System.currentTimeMillis()-start}ms",
                    )
                } finally {
                    c.disconnect()
                }
            }
        }
    }
}
