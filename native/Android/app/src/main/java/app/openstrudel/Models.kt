package app.openstrudel

import java.net.URI
import java.net.URLDecoder
import java.net.URLEncoder
import java.util.UUID
import org.json.JSONArray
import org.json.JSONObject

fun JSONObject.string(key: String): String? =
    if (isNull(key)) null else optString(key).takeIf { it.isNotEmpty() }

fun JSONObject.objects(key: String): List<JSONObject> =
    optJSONArray(key)?.let { a -> (0 until a.length()).mapNotNull { a.optJSONObject(it) } }
        ?: emptyList()

fun JSONObject.strings(key: String): List<String> =
    optJSONArray(key)?.let { a -> (0 until a.length()).map { a.getString(it) } } ?: emptyList()

fun json(vararg fields: Pair<String, Any?>) =
    JSONObject().apply { fields.forEach { (k, v) -> put(k, v ?: JSONObject.NULL) } }

fun encoded(value: String): String = URLEncoder.encode(value, "UTF-8").replace("+", "%20")

/** The same strict invitation format used by the native Apple clients. */
data class Invitation(
    val host: String,
    val port: Int,
    val key: String,
    val pin: String,
    val name: String,
) {
    val baseUrl
        get() = "https://$host:$port"

    override fun toString() = "Invitation(name=$name)"

    companion object {
        fun parse(value: String): Invitation {
            require(value.length <= 4096) { "Это не приглашение OpenStrudel." }
            var u = URI(value.trim())
            if (u.scheme == "https") {
                require(
                    u.host == "waiwai.is" &&
                        u.path == "/openstrudel/connect.html" &&
                        u.rawQuery == null &&
                        u.userInfo == null &&
                        u.port in listOf(-1, 443)
                ) {
                    "Это не приглашение OpenStrudel."
                }
                u = URI(URLDecoder.decode(requireNotNull(u.rawFragment), "UTF-8"))
            }
            require(
                u.scheme == "openstrudel" &&
                    u.host == "connect" &&
                    u.path.isNullOrEmpty() &&
                    u.fragment == null &&
                    u.userInfo == null &&
                    u.port == -1
            ) {
                "Используйте ссылку из OpenStrudel на компьютере."
            }
            val pairs =
                (u.rawQuery ?: "").split('&').map { item ->
                    val pieces = item.split('=', limit = 2)
                    require(pieces.size == 2)
                    URLDecoder.decode(pieces[0], "UTF-8") to URLDecoder.decode(pieces[1], "UTF-8")
                }
            require(pairs.map { it.first }.toSet().size == pairs.size) {
                "В приглашении повторяются параметры."
            }
            val p = pairs.toMap()
            val host = requireNotNull(p["host"])
            require(
                host.length <= 253 &&
                    host.split('.').all {
                        it.length in 1..63 &&
                            Regex("^[a-zA-Z0-9](?:[a-zA-Z0-9-]*[a-zA-Z0-9])?$").matches(it)
                    }
            )
            val port = requireNotNull(p["port"]?.toIntOrNull())
            require(port in 1..65535)
            val key = requireNotNull(p["key"])
            val pin = requireNotNull(p["pin"])
            val hash = Regex("^[a-f0-9]{64}$")
            require(hash.matches(key) && hash.matches(pin))
            val keyPin = p["keyPin"]
            require(keyPin == null || hash.matches(keyPin))
            return Invitation(
                host,
                port,
                key,
                keyPin?.let { "spki:$it" } ?: pin,
                p["name"]?.trim()?.take(80)?.takeIf { it.isNotBlank() }
                    ?: host.removeSuffix(".local"),
            )
        }
    }
}

data class Connection(
    val id: String,
    val url: String,
    val token: String,
    val pin: String,
    val name: String,
) {
    fun toJson() = json("id" to id, "url" to url, "token" to token, "pin" to pin, "name" to name)

    override fun toString() = "Connection(id=$id, name=$name)"

    companion object {
        fun from(j: JSONObject) =
            Connection(
                j.getString("id"),
                j.getString("url"),
                j.getString("token"),
                j.getString("pin"),
                j.getString("name"),
            )
    }
}

data class Employee(
    val id: String,
    val name: String,
    val instructions: String,
    val preview: String,
    val character: String,
    val deviceId: String?,
) {
    companion object {
        fun from(j: JSONObject) =
            Employee(
                j.getString("id"),
                j.string("name") ?: "OpenStrudel",
                j.string("instructions") ?: "",
                j.string("preview") ?: "",
                j.optJSONObject("appearance")?.string("kind") ?: "coil",
                j.string("deviceId"),
            )
    }
}

data class Attachment(val id: String, val name: String, val mimeType: String, val size: Long) {
    companion object {
        fun from(j: JSONObject) =
            Attachment(
                j.getString("id"),
                j.getString("name"),
                j.optString("mimeType", "application/octet-stream"),
                j.optLong("size"),
            )
    }
}

data class Message(
    val id: String,
    val conversationId: String,
    val text: String,
    val inbound: Boolean,
    val date: String,
    val status: String,
    val channel: String,
    val externalId: String?,
    val error: String?,
    val origin: String?,
    val author: String?,
    val files: List<Attachment>,
) {
    val working
        get() = status in listOf("queued", "running")

    companion object {
        fun from(j: JSONObject) =
            Message(
                j.getString("id"),
                j.getString("conversationId"),
                j.optString("text"),
                j.optString("direction") == "inbound",
                j.optString("createdAt"),
                j.optString("status"),
                j.optString("channel"),
                j.string("externalId"),
                j.string("error"),
                j.optJSONObject("origin")?.string("title"),
                j.string("author"),
                j.objects("attachments").map(Attachment::from),
            )
    }
}

fun mergeMessages(
    existing: List<Message>,
    page: List<Message>,
    updates: List<Message> = emptyList(),
    removed: Set<String> = emptySet(),
    prepend: Boolean = false,
): List<Message> {
    val map = linkedMapOf<String, Message>()
    (if (prepend) page + existing else existing + page).forEach {
        if (it.id !in removed) map[it.id] = it
    }
    updates.forEach { if (it.id !in removed) map[it.id] = it }
    return map.values.toList()
}

data class LocalFile(
    val id: String = UUID.randomUUID().toString(),
    val name: String,
    val mimeType: String,
    val path: String,
    val size: Long,
) {
    fun toJson() =
        json("id" to id, "name" to name, "mimeType" to mimeType, "path" to path, "size" to size)

    companion object {
        fun from(j: JSONObject) =
            LocalFile(
                j.getString("id"),
                j.getString("name"),
                j.getString("mimeType"),
                j.getString("path"),
                j.getLong("size"),
            )
    }
}

data class PendingSend(
    val id: String = UUID.randomUUID().toString(),
    val home: String,
    val employee: String,
    val conversation: String?,
    val text: String,
    val mode: String,
    val files: List<LocalFile>,
    val error: String? = null,
    val operationId: String? = null,
) {
    fun toJson() =
        json(
            "id" to id,
            "home" to home,
            "employee" to employee,
            "conversation" to conversation,
            "text" to text,
            "mode" to mode,
            "files" to JSONArray(files.map { it.toJson() }),
            "error" to error,
            "operationId" to operationId,
        )

    companion object {
        fun from(j: JSONObject) =
            PendingSend(
                j.getString("id"),
                j.getString("home"),
                j.getString("employee"),
                j.string("conversation"),
                j.optString("text"),
                j.optString("mode", "steer"),
                j.objects("files").map(LocalFile::from),
                j.string("error"),
                j.string("operationId"),
            )
    }
}

data class Draft(
    val text: String = "",
    val files: List<LocalFile> = emptyList(),
    val recording: LocalFile? = null,
) {
    fun toJson() =
        json(
            "text" to text,
            "files" to JSONArray(files.map { it.toJson() }),
            "recording" to recording?.toJson(),
        )

    companion object {
        fun from(j: JSONObject) =
            Draft(
                j.optString("text"),
                j.objects("files").map(LocalFile::from),
                j.optJSONObject("recording")?.let(LocalFile::from),
            )
    }
}

data class PairAttempt(val candidate: Connection, val nonce: String) {
    fun toJson() = json("candidate" to candidate.toJson(), "nonce" to nonce)

    fun invitation(): Invitation {
        val u = URI(candidate.url)
        return Invitation(u.host, u.port, candidate.token, candidate.pin, candidate.name)
    }

    companion object {
        fun from(j: JSONObject) =
            PairAttempt(Connection.from(j.getJSONObject("candidate")), j.getString("nonce"))
    }
}

data class StoredState(
    val connections: List<Connection> = emptyList(),
    val drafts: Map<String, Draft> = emptyMap(),
    val hidden: Set<String> = emptySet(),
    val pending: List<PendingSend> = emptyList(),
    val pairing: PairAttempt? = null,
    val oauth: List<String>? = null,
) {
    fun toJson() =
        json(
            "version" to 1,
            "connections" to JSONArray(connections.map { it.toJson() }),
            "drafts" to JSONObject().apply { drafts.forEach { (k, v) -> put(k, v.toJson()) } },
            "hidden" to JSONArray(hidden.toList()),
            "pending" to JSONArray(pending.map { it.toJson() }),
            "pairing" to pairing?.toJson(),
            "oauth" to oauth?.let { JSONArray(it) },
        )

    companion object {
        fun from(j: JSONObject): StoredState {
            require(j.getInt("version") == 1) {
                "Обновите приложение, чтобы открыть сохранённые подключения."
            }
            val drafts = j.optJSONObject("drafts") ?: JSONObject()
            return StoredState(
                j.objects("connections").map(Connection::from),
                drafts.keys().asSequence().associateWith { Draft.from(drafts.getJSONObject(it)) },
                j.strings("hidden").toSet(),
                j.objects("pending").map(PendingSend::from),
                j.optJSONObject("pairing")?.let(PairAttempt::from),
                j.strings("oauth").takeIf { it.size == 3 },
            )
        }
    }
}

fun chatKey(home: String, employee: String) = "$home/$employee"
