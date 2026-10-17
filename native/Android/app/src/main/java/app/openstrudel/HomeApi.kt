package app.openstrudel

import java.io.IOException
import java.net.URI
import java.security.MessageDigest
import java.security.cert.CertificateException
import java.security.cert.X509Certificate
import java.util.Base64
import java.util.UUID
import java.util.concurrent.TimeUnit
import javax.net.ssl.SSLContext
import javax.net.ssl.SSLException
import javax.net.ssl.X509TrustManager
import kotlin.coroutines.resume
import kotlin.coroutines.resumeWithException
import kotlinx.coroutines.delay
import kotlinx.coroutines.suspendCancellableCoroutine
import okhttp3.Call
import okhttp3.Callback
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.Response
import org.json.JSONObject

class HomeFailure(val status: Int, message: String) : IOException(message)

data class ApiReply(val code: Int, val json: JSONObject, val etag: String?)

class PinTrust(private val pin: String) : X509TrustManager {
    override fun getAcceptedIssuers(): Array<X509Certificate> = emptyArray()

    override fun checkClientTrusted(chain: Array<out X509Certificate>?, authType: String?) =
        throw CertificateException("Client certificates are not supported")

    override fun checkServerTrusted(chain: Array<out X509Certificate>?, authType: String?) {
        val leaf = chain?.firstOrNull() ?: throw CertificateException("Missing Home certificate")
        leaf.checkValidity()
        val expected = pin.removePrefix("spki:")
        if (!Regex("[a-f0-9]{64}").matches(expected)) throw CertificateException("Invalid Home pin")
        val bytes = if (pin.startsWith("spki:")) leaf.publicKey.encoded else leaf.encoded
        val actual =
            MessageDigest.getInstance("SHA-256").digest(bytes).joinToString("") {
                "%02x".format(it.toInt() and 255)
            }
        if (!MessageDigest.isEqual(expected.toByteArray(), actual.toByteArray()))
            throw CertificateException("Home identity changed")
    }
}

/** Per-Home TLS trust. Pins are never installed in a global trust store. */
class HomeApi(val connection: Connection) {
    private val closed = java.util.concurrent.atomic.AtomicBoolean(false)
    private val origin = URI(connection.url)

    init {
        require(
            origin.scheme == "https" &&
                origin.host != null &&
                origin.userInfo == null &&
                origin.rawQuery == null &&
                origin.fragment == null &&
                origin.path.isNullOrEmpty()
        )
    }

    private val trust = PinTrust(connection.pin)
    private val tls = SSLContext.getInstance("TLS").apply { init(null, arrayOf(trust), null) }
    private val client =
        OkHttpClient.Builder()
            .sslSocketFactory(tls.socketFactory, trust)
            .hostnameVerifier { host, session ->
                host.equals(origin.host, true) &&
                    runCatching {
                            trust.checkServerTrusted(
                                arrayOf(session.peerCertificates[0] as X509Certificate),
                                null,
                            )
                            true
                        }
                        .getOrDefault(false)
            }
            .followRedirects(false)
            .followSslRedirects(false)
            .retryOnConnectionFailure(true)
            .connectTimeout(10, TimeUnit.SECONDS)
            .readTimeout(200, TimeUnit.SECONDS)
            .callTimeout(210, TimeUnit.SECONDS)
            .build()

    private suspend fun execute(request: Request): Response =
        suspendCancellableCoroutine { continuation ->
            if (closed.get()) {
                continuation.resumeWithException(IOException("Home connection closed"))
                return@suspendCancellableCoroutine
            }
            val call = client.newCall(request)
            call
                .timeout()
                .timeout(
                    if (request.url.encodedPath == "/v1/speech/transcribe") 210 else 35,
                    TimeUnit.SECONDS,
                )
            continuation.invokeOnCancellation { call.cancel() }
            call.enqueue(
                object : Callback {
                    override fun onFailure(call: Call, e: IOException) {
                        if (continuation.isActive) continuation.resumeWithException(e)
                    }

                    override fun onResponse(call: Call, response: Response) {
                        if (continuation.isActive)
                            continuation.resume(response) { _, value, _ -> value.close() }
                        else response.close()
                    }
                }
            )
        }

    private fun request(
        path: String,
        method: String,
        body: JSONObject?,
        id: String?,
        etag: String?,
    ): Request {
        require(path.startsWith('/') && !path.startsWith("//") && '\\' !in path)
        val builder =
            Request.Builder()
                .url(connection.url + path)
                .header("Authorization", "Bearer " + connection.token)
        if (etag != null) builder.header("If-None-Match", etag)
        if (method != "GET") builder.header("Idempotency-Key", id ?: UUID.randomUUID().toString())
        return builder
            .method(
                method,
                if (method == "GET") null
                else
                    object : okhttp3.RequestBody() {
                        private val bytes =
                            (body ?: JSONObject()).toString().toByteArray(Charsets.UTF_8)

                        override fun contentType() = "application/json".toMediaType()

                        override fun contentLength() = bytes.size.toLong()

                        // Recovery may reconnect before sending; an ambiguous write must not be
                        // replayed.
                        override fun isOneShot() = true

                        override fun writeTo(sink: okio.BufferedSink) {
                            sink.write(bytes)
                        }
                    },
            )
            .build()
    }

    suspend fun pair(nonce: String, deviceName: String): String {
        val r =
            request("/pair", "POST", json("name" to deviceName), nonce, null)
                .newBuilder()
                .header("X-OpenStrudel-Pair-ID", nonce)
                .build()
        execute(r).use { response ->
            val source = response.body?.source() ?: throw IOException("Пустой ответ")
            val buffer = okio.Buffer()
            while (true) {
                val n = source.read(buffer, 8192)
                if (n < 0) break
                if (buffer.size > 65536) throw IOException("Ответ слишком большой")
            }
            val text = buffer.readUtf8()
            if (!response.isSuccessful)
                throw HomeFailure(
                    response.code,
                    runCatching { JSONObject(text).string("error") }.getOrNull()
                        ?: "Не удалось подключить устройство.",
                )
            return JSONObject(text).getString("token").also {
                require(Regex("[a-f0-9]{64}").matches(it))
            }
        }
    }

    suspend fun call(
        path: String,
        method: String = "GET",
        body: JSONObject? = null,
        id: String? = null,
        etag: String? = null,
    ): ApiReply {
        execute(request(path, method, body, id, etag)).use { response ->
            if (response.code == 304)
                return ApiReply(304, JSONObject(), response.header("ETag") ?: etag)
            val source = response.body?.source() ?: throw IOException("Пустой ответ устройства")
            val buffer = okio.Buffer()
            while (true) {
                val n = source.read(buffer, 8192)
                if (n < 0) break
                if (buffer.size > 16L * 1024 * 1024)
                    throw IOException("Ответ слишком большой. Откройте более короткую историю.")
            }
            val data = buffer.readByteArray()
            val result = runCatching {
                JSONObject(String(data, Charsets.UTF_8))
            }
                .getOrElse {
                    if (response.code == 204) JSONObject()
                    else throw IOException("Не удалось прочитать ответ устройства.")
                }
            if (!response.isSuccessful) {
                val message =
                    when (response.code) {
                        401 -> "Подключение отозвано. Получите новое приглашение на компьютере."
                        in 300..399 -> "Адрес устройства изменился. Используйте новое приглашение."
                        else ->
                            result.string("error")
                                ?: "Устройство не выполнило запрос (${response.code})."
                    }
                throw HomeFailure(response.code, message)
            }
            return ApiReply(response.code, result, response.header("ETag"))
        }
    }

    suspend fun action(
        path: String,
        method: String = "POST",
        body: JSONObject? = null,
        id: String = UUID.randomUUID().toString(),
    ): JSONObject {
        val reply = call(path, method, body, id)
        val operation = reply.json.string("operationId")
        if (reply.code != 202 || operation == null) return reply.json
        repeat(30) {
            delay(1000)
            val status = call("/v1/home/requests/" + encoded(operation)).json
            if (status.optString("status") == "canceled")
                throw HomeFailure(409, "Действие отменено до передачи устройству.")
            status.optJSONObject("response")?.let { r ->
                val value =
                    JSONObject(
                        String(Base64.getDecoder().decode(r.getString("body")), Charsets.UTF_8)
                    )
                if (r.getInt("status") >= 400)
                    throw HomeFailure(
                        r.getInt("status"),
                        value.string("error") ?: "Проверьте результат перед повтором.",
                    )
                return value
            }
        }
        throw HomeFailure(
            202,
            "Устройство ещё выполняет действие. Проверьте результат перед повтором.",
        )
    }

    suspend fun file(id: String): ByteArray {
        execute(request("/v1/files/" + encoded(id), "GET", null, null, null)).use { r ->
            if (!r.isSuccessful)
                throw HomeFailure(r.code, "Не удалось открыть файл. Попробуйте ещё раз.")
            val source = r.body?.source() ?: throw IOException("Файл пуст")
            val buffer = okio.Buffer()
            while (true) {
                val n = source.read(buffer, 8192)
                if (n < 0) break
                if (buffer.size > 30L * 1024 * 1024)
                    throw IOException("Этот файл больше 30 МБ. Откройте его на компьютере.")
            }
            return buffer.readByteArray()
        }
    }

    fun close() {
        if (!closed.compareAndSet(false, true)) return
        // TLS socket shutdown may write a close_notify record. Keep it off the UI thread,
        // including when Android destroys the activity or a Home is removed.
        client.dispatcher.executorService.execute {
            client.dispatcher.cancelAll()
            client.connectionPool.evictAll()
            client.dispatcher.executorService.shutdown()
        }
    }
}

fun friendlyError(error: Throwable): String =
    when (error) {
        is HomeFailure -> error.message ?: "Не удалось выполнить действие."
        is SSLException -> "Не удалось подтвердить устройство. Получите новое приглашение."
        is java.net.SocketTimeoutException ->
            "Устройство отвечает дольше обычного. Проверьте результат перед повтором."
        is IOException -> "Нет связи с устройством. Попробуйте ещё раз."
        else -> "Не удалось выполнить действие. Попробуйте ещё раз."
    }
