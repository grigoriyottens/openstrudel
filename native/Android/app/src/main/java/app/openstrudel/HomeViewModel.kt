package app.openstrudel

import android.app.Application
import android.net.Uri
import android.provider.OpenableColumns
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import java.io.File
import java.io.IOException
import java.util.Base64
import java.util.UUID
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.async
import kotlinx.coroutines.awaitAll
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withContext
import org.json.JSONArray
import org.json.JSONObject

data class HomeView(
    val employees: List<Employee> = emptyList(),
    val health: JSONObject? = null,
    val etag: String? = null,
    val online: Boolean = false,
    val canManage: Boolean = false,
    val error: String? = null,
)

data class ChatView(
    val conversation: String? = null,
    val messages: List<Message> = emptyList(),
    val older: String? = null,
    val newer: String? = null,
    val loaded: Boolean = false,
    val loading: Boolean = false,
    val error: String? = null,
    val effective: JSONObject? = null,
)

data class ChatRef(val home: String, val employee: String) {
    val key
        get() = chatKey(home, employee)
}

data class AppState(
    val loaded: Boolean = false,
    val stored: StoredState = StoredState(),
    val drafts: Map<String, Draft> = emptyMap(),
    val homes: Map<String, HomeView> = emptyMap(),
    val chats: Map<String, ChatView> = emptyMap(),
    val invitation: Invitation? = null,
    val pairing: Boolean = false,
    val notice: String? = null,
    val fatal: String? = null,
    val transcribing: Set<String> = emptySet(),
    val sending: Set<String> = emptySet(),
)

/** UI state is scoped by Home and employee; the server remains the sole engine. */
class HomeViewModel(application: Application) : AndroidViewModel(application) {
    private val vault = SecureState(application)
    private val lock = Mutex()
    private val sends = Mutex()
    private val requests = mutableMapOf<String, Mutex>()
    private val clients = java.util.concurrent.ConcurrentHashMap<String, HomeApi>()
    private val _state = MutableStateFlow(AppState())
    val state = _state.asStateFlow()
    private var visible: ChatRef? = null
    private var draftSave: Job? = null
    private var pairNonce = UUID.randomUUID().toString()
    private var pairCredential: Connection? = null
    private var pendingOAuth: String? = null
    private val generation = mutableMapOf<String, Int>()

    init {
        load()
    }

    fun load() {
        viewModelScope.launch {
            try {
                val saved = withContext(Dispatchers.IO) { vault.read() }
                saved.pairing
                    ?.takeIf {
                        _state.value.invitation == null ||
                            _state.value.invitation == it.invitation()
                    }
                    ?.let { pairNonce = it.nonce }
                _state.update {
                    it.copy(
                        loaded = true,
                        stored = saved,
                        drafts = saved.drafts,
                        fatal = null,
                        invitation = it.invitation ?: saved.pairing?.invitation(),
                    )
                }
                io { pruneDraftFiles(saved) }
                pendingOAuth?.let {
                    pendingOAuth = null
                    completeOAuth(it)
                }
                refresh()
                drain()
            } catch (e: Exception) {
                if (e is CancellationException) throw e
                _state.update {
                    it.copy(
                        loaded = true,
                        fatal =
                            "Не удалось открыть сохранённые подключения. Повторите попытку; данные сохранены.",
                    )
                }
            }
        }
    }

    private suspend fun persist(change: (StoredState) -> StoredState) = lock.withLock {
        val next = change(_state.value.stored)
        withContext(Dispatchers.IO) { vault.write(next) }
        _state.update { it.copy(stored = next) }
    }

    private fun connection(id: String) = _state.value.stored.connections.firstOrNull { it.id == id }

    private fun api(id: String): HomeApi {
        val c = connection(id) ?: throw HomeFailure(410, "Подключение удалено с этого телефона.")
        return clients.getOrPut(id) { HomeApi(c) }
    }

    private suspend fun <T> io(block: suspend () -> T): T = withContext(Dispatchers.IO) { block() }

    private fun launchAction(block: suspend () -> Unit) {
        viewModelScope.launch {
            try {
                block()
            } catch (e: Exception) {
                if (e is CancellationException) throw e
                notice(friendlyError(e))
            }
        }
    }

    fun notice(text: String?) {
        _state.update { it.copy(notice = text) }
    }

    fun inspectLink(link: String) {
        if (link.startsWith("openstrudel://oauth/")) {
            if (_state.value.loaded) completeOAuth(link) else pendingOAuth = link
            return
        }
        try {
            val invite = Invitation.parse(link)
            pairNonce =
                _state.value.stored.pairing?.takeIf { it.invitation() == invite }?.nonce
                    ?: UUID.randomUUID().toString()
            pairCredential = null
            _state.update { it.copy(invitation = invite, notice = null) }
        } catch (_: Exception) {
            notice("Это не приглашение OpenStrudel. Получите новую ссылку на компьютере.")
        }
    }

    fun dismissInvitation() {
        if (!_state.value.pairing) {
            _state.update { it.copy(invitation = null) }
            launchAction { persist { it.copy(pairing = null) } }
        }
    }

    fun pair() {
        if (_state.value.pairing || !_state.value.loaded || _state.value.fatal != null) return
        val invite = _state.value.invitation ?: return
        _state.update { it.copy(pairing = true, notice = null) }
        launchAction {
            try {
                if (
                    _state.value.stored.connections.any {
                        it.url == invite.baseUrl && it.pin == invite.pin
                    }
                ) {
                    notice("Это устройство уже подключено.")
                    _state.update { it.copy(invitation = null) }
                    return@launchAction
                }
                val attempt =
                    _state.value.stored.pairing?.takeIf { it.nonce == pairNonce }
                        ?: PairAttempt(
                                Connection(
                                    UUID.randomUUID().toString(),
                                    invite.baseUrl,
                                    invite.key,
                                    invite.pin,
                                    invite.name,
                                ),
                                pairNonce,
                            )
                            .also { attempt -> persist { it.copy(pairing = attempt) } }
                val connected =
                    pairCredential
                        ?: io {
                            val temporary = HomeApi(attempt.candidate)
                            try {
                                temporary.pair(pairNonce, android.os.Build.MODEL).let { token ->
                                    temporary.connection.copy(token = token)
                                }
                            } finally {
                                temporary.close()
                            }
                        }
                            .also { pairCredential = it }
                persist { it.copy(connections = it.connections + connected, pairing = null) }
                pairCredential = null
                _state.update { it.copy(invitation = null) }
                refreshHome(connected.id)
            } finally {
                _state.update { it.copy(pairing = false) }
            }
        }
    }

    fun removeHome(id: String) {
        launchAction {
            val c = connection(id) ?: return@launchAction
            // Commit first. Neither a delayed health response nor logout can add it back.
            persist { s ->
                s.copy(
                    connections = s.connections.filterNot { it.id == id },
                    drafts = s.drafts.filterKeys { !it.startsWith("$id/") },
                    hidden = s.hidden.filterNot { it.startsWith("$id/") }.toSet(),
                    pending = s.pending.filterNot { it.home == id },
                    oauth = s.oauth?.takeUnless { it.firstOrNull() == id },
                )
            }
            generation[id] = (generation[id] ?: 0) + 1
            if (visible?.home == id) visible = null
            clients.remove(id)?.close()
            _state.update {
                it.copy(
                    homes = it.homes - id,
                    chats = it.chats.filterKeys { k -> !k.startsWith("$id/") },
                    drafts = it.drafts.filterKeys { k -> !k.startsWith("$id/") },
                )
            }
            // Failure cannot restore the connection locally. Owner can revoke it on Home.
            io {
                val remote = HomeApi(c)
                try {
                    remote.call("/auth/device/logout", "POST")
                } catch (_: IOException) {} finally {
                    remote.close()
                }
            }
        }
    }

    fun saveDraft(ref: ChatRef, draft: Draft) {
        _state.update { it.copy(drafts = it.drafts + (ref.key to draft)) }
        draftSave?.cancel()
        draftSave = viewModelScope.launch {
            delay(250)
            flushDrafts()
        }
    }

    suspend fun flushDrafts() {
        if (!_state.value.loaded || _state.value.fatal != null) return
        try {
            persist { it.copy(drafts = _state.value.drafts) }
        } catch (e: Exception) {
            if (e is CancellationException) throw e
            notice("Не удалось сохранить черновик на телефоне. Освободите место.")
        }
    }

    fun hide(ref: ChatRef, hidden: Boolean) {
        launchAction {
            persist { s -> s.copy(hidden = if (hidden) s.hidden + ref.key else s.hidden - ref.key) }
        }
    }

    fun setVisible(ref: ChatRef?) {
        visible = ref
        if (ref != null) launchAction { refreshChat(ref) }
    }

    suspend fun foregroundLoop(): Unit = coroutineScope {
        var tick = 0
        while (true) {
            if (_state.value.loaded && _state.value.fatal == null) {
                if (tick % 4 == 0) launch { refresh() }
                visible?.let { refreshChat(it) }
                checkPending()
            }
            delay(
                if (
                    visible?.let { _state.value.chats[it.key]?.messages?.any { m -> m.working } } ==
                        true
                )
                    1500
                else 4000
            )
            tick++
        }
    }

    fun refreshNow() {
        launchAction {
            refresh()
            visible?.let { refreshChat(it) }
            checkPending()
        }
    }

    private suspend fun refresh() = coroutineScope {
        // A phone usually has one or two Homes; each has its own bounded connection pool.
        _state.value.stored.connections.chunked(2).forEach { pair ->
            pair.map { async { refreshHome(it.id) } }.awaitAll()
        }
    }

    private suspend fun refreshHome(id: String) {
        val mutex = requests.getOrPut("home:" + id) { Mutex() }
        if (!mutex.tryLock()) return
        try {
            val c = connection(id) ?: return
            val version = generation[id] ?: 0
            val current = _state.value.homes[id] ?: HomeView()
            fun stillCurrent() = connection(id) == c && (generation[id] ?: 0) == version
            val service = api(id)
            val result =
                try {
                    io { service.call("/v1/profiles", etag = current.etag) }
                } catch (e: Exception) {
                    if (e is CancellationException) throw e
                    if (stillCurrent())
                        _state.update {
                            it.copy(
                                homes =
                                    it.homes +
                                        (id to
                                            current.copy(online = false, error = friendlyError(e)))
                            )
                        }
                    return
                }
            if (!stillCurrent()) return
            val employees =
                if (result.code == 304) current.employees
                else result.json.objects("profiles").map(Employee::from)
            // A verified catalogue response already proves that Home is reachable. Optional
            // capability/account reads must neither delay its list nor mark it offline.
            _state.update {
                it.copy(
                    homes =
                        it.homes +
                            (id to
                                current.copy(
                                    employees = employees,
                                    etag = result.etag,
                                    online = true,
                                    error = null,
                                ))
                )
            }
            if (current.health == null || !current.online) {
                try {
                    val health = io { service.call("/health").json }
                    val manage = io {
                        service.call("/v1/account").json.optBoolean("canManage", false)
                    }
                    if (stillCurrent())
                        _state.update { s ->
                            val latest = s.homes[id] ?: return@update s
                            s.copy(
                                homes =
                                    s.homes +
                                        (id to latest.copy(health = health, canManage = manage))
                            )
                        }
                } catch (e: Exception) {
                    if (e is CancellationException) throw e
                }
            }
        } finally {
            mutex.unlock()
        }
    }

    suspend fun refreshChat(ref: ChatRef, earlier: Boolean = false) {
        if (connection(ref.home) == null) return
        val mutex = requests.getOrPut(ref.key) { Mutex() }
        if (!mutex.tryLock()) return
        try {
            val c = connection(ref.home)
            val version = generation[ref.home] ?: 0
            val old = _state.value.chats[ref.key] ?: ChatView()
            if (earlier && old.older == null) return
            _state.update { it.copy(chats = it.chats + (ref.key to old.copy(loading = true))) }
            var path =
                (if (ref.employee == "main") "/v1/conversation"
                else "/v1/agents/" + encoded(ref.employee) + "/conversation") +
                    "?page=true&limit=50"
            if (_state.value.homes[ref.home]?.health?.optInt("employeeTimelineVersion") == 1)
                path += "&timeline=true"
            if (earlier) path += "&before=" + encoded(old.older!!)
            else if (old.newer != null) path += "&after=" + encoded(old.newer)
            val watch = old.messages.filter { it.working }.take(200).joinToString(",") { it.id }
            if (watch.isNotEmpty()) path += "&watch=" + encoded(watch)
            val page = io { api(ref.home).call(path).json }
            if (connection(ref.home) != c || (generation[ref.home] ?: 0) != version) return
            val pagination = page.optJSONObject("pagination")
            val incoming = page.objects("messages").map(Message::from)
            val messages =
                mergeMessages(
                    if (old.loaded) old.messages else emptyList(),
                    incoming,
                    page.objects("updates").map(Message::from),
                    page.strings("removedIds").toSet(),
                    earlier,
                )
            val chat = page.getJSONObject("conversation")
            _state.update {
                it.copy(
                    chats =
                        it.chats +
                            (ref.key to
                                ChatView(
                                    chat.getString("id"),
                                    messages,
                                    if (earlier || !old.loaded) pagination?.string("olderCursor")
                                    else old.older,
                                    if (earlier) old.newer else pagination?.string("newerCursor"),
                                    true,
                                    false,
                                    null,
                                    chat.optJSONObject("effectiveModel"),
                                ))
                )
            }
            val delivered = messages.mapNotNull { it.externalId }.toSet()
            if (_state.value.stored.pending.any { it.home == ref.home && it.id in delivered })
                persist { s ->
                    s.copy(
                        pending = s.pending.filterNot { it.home == ref.home && it.id in delivered }
                    )
                }
        } catch (e: Exception) {
            if (e is CancellationException) throw e
            if (connection(ref.home) != null)
                _state.update { s ->
                    s.copy(
                        chats =
                            s.chats +
                                (ref.key to
                                    (s.chats[ref.key] ?: ChatView()).copy(
                                        loading = false,
                                        error = friendlyError(e),
                                    ))
                    )
                }
        } finally {
            mutex.unlock()
        }
    }

    fun earlier(ref: ChatRef) {
        launchAction { refreshChat(ref, true) }
    }

    suspend fun create(
        home: String,
        name: String,
        instructions: String,
        requestId: String,
    ): String {
        val j = io {
            api(home)
                .action(
                    "/v1/profiles",
                    body =
                        json(
                            "creationId" to requestId,
                            "name" to name.trim(),
                            "instructions" to instructions.trim(),
                        ),
                    id = requestId,
                )
        }
        applyProfile(home, Employee.from(j.getJSONObject("profile")))
        return j.getJSONObject("profile").getString("id")
    }

    suspend fun edit(ref: ChatRef, name: String, instructions: String) {
        val response = io {
            api(ref.home)
                .action(
                    "/v1/profiles/" + encoded(ref.employee),
                    "PATCH",
                    json("name" to name.trim(), "instructions" to instructions.trim()),
                )
        }
        applyProfile(ref.home, Employee.from(response.getJSONObject("profile")))
    }

    private fun applyProfile(home: String, profile: Employee) {
        if (connection(home) == null) return
        generation[home] = (generation[home] ?: 0) + 1
        _state.update { s ->
            val current = s.homes[home] ?: HomeView()
            s.copy(
                homes =
                    s.homes +
                        (home to
                            current.copy(
                                employees =
                                    current.employees.filterNot { it.id == profile.id } + profile,
                                etag = null,
                            ))
            )
        }
    }

    fun delete(ref: ChatRef, onDone: () -> Unit) {
        launchAction {
            require(ref.employee != "main")
            io { api(ref.home).action("/v1/profiles/" + encoded(ref.employee), "DELETE") }
            generation[ref.home] = (generation[ref.home] ?: 0) + 1
            persist { s ->
                s.copy(
                    drafts = s.drafts - ref.key,
                    hidden = s.hidden - ref.key,
                    pending =
                        s.pending.filterNot { it.home == ref.home && it.employee == ref.employee },
                )
            }
            _state.update { it.copy(chats = it.chats - ref.key, drafts = it.drafts - ref.key) }
            visible = null
            _state.update { s ->
                val current = s.homes[ref.home] ?: return@update s
                s.copy(
                    homes =
                        s.homes +
                            (ref.home to
                                current.copy(
                                    employees =
                                        current.employees.filterNot { it.id == ref.employee },
                                    etag = null,
                                ))
                )
            }
            onDone()
        }
    }

    fun send(ref: ChatRef, mode: String = "steer") {
        if (ref.key in _state.value.sending) return
        val draft = _state.value.drafts[ref.key] ?: Draft()
        if (draft.text.isBlank() && draft.files.isEmpty()) return
        _state.update { it.copy(sending = it.sending + ref.key) }
        launchAction {
            try {
                val pending =
                    PendingSend(
                        home = ref.home,
                        employee = ref.employee,
                        conversation = _state.value.chats[ref.key]?.conversation,
                        text = draft.text.trim(),
                        mode = mode,
                        files = draft.files,
                    )
                persist { s ->
                    s.copy(
                        pending = s.pending + pending,
                        drafts =
                            _state.value.drafts + (ref.key to Draft(recording = draft.recording)),
                    )
                }
                _state.update { s ->
                    if (s.drafts[ref.key] == draft)
                        s.copy(drafts = s.drafts + (ref.key to Draft(recording = draft.recording)))
                    else s
                }
                drain()
            } finally {
                _state.update { it.copy(sending = it.sending - ref.key) }
            }
        }
    }

    fun retrySend(id: String) {
        launchAction {
            persist { s ->
                s.copy(pending = s.pending.map { if (it.id == id) it.copy(error = null) else it })
            }
            drain()
        }
    }

    private suspend fun drain() {
        if (!sends.tryLock()) return
        try {
            while (true) {
                val p =
                    _state.value.stored.pending.firstOrNull {
                        it.error == null && it.operationId == null
                    } ?: break
                try {
                    val service = api(p.home)
                    val result = io {
                        val conversation =
                            p.conversation
                                ?: service
                                    .call(
                                        if (p.employee == "main") "/v1/conversation"
                                        else "/v1/agents/" + encoded(p.employee) + "/conversation"
                                    )
                                    .json
                                    .getJSONObject("conversation")
                                    .getString("id")
                        val ids =
                            p.files.map { f ->
                                val data = File(f.path).readBytes()
                                service
                                    .action(
                                        "/v1/conversations/" + encoded(conversation) + "/files",
                                        body =
                                            json(
                                                "id" to f.id,
                                                "name" to f.name,
                                                "mimeType" to f.mimeType,
                                                "contentBase64" to
                                                    Base64.getEncoder().encodeToString(data),
                                            ),
                                        id = f.id,
                                    )
                                    .getJSONObject("attachment")
                                    .getString("id")
                            }
                        val payload =
                            json(
                                "channel" to "api",
                                "externalChatId" to "home",
                                "externalId" to p.id,
                                "text" to p.text,
                                "conversationId" to conversation,
                                "attachments" to JSONArray(ids),
                            )
                        if (p.employee != "main") payload.put("profile", p.employee)
                        if (_state.value.homes[p.home]?.health?.optInt("turnControlVersion") == 1)
                            payload.put("mode", p.mode)
                        service.call("/v1/messages?async=true", "POST", payload, p.id).json
                    }
                    persist { s ->
                        val operation = result.string("operationId")
                        s.copy(
                            pending =
                                if (operation == null) s.pending.filterNot { it.id == p.id }
                                else
                                    s.pending.map {
                                        if (it.id == p.id) it.copy(operationId = operation) else it
                                    }
                        )
                    }
                    refreshChat(ChatRef(p.home, p.employee))
                } catch (e: Exception) {
                    if (e is CancellationException) throw e
                    persist { s ->
                        s.copy(
                            pending =
                                s.pending.map {
                                    if (it.id == p.id)
                                        it.copy(
                                            error =
                                                friendlyError(e) +
                                                    " Повтор проверит это же сообщение."
                                        )
                                    else it
                                }
                        )
                    }
                }
            }
        } finally {
            sends.unlock()
        }
    }

    private suspend fun checkPending() {
        for (p in
            _state.value.stored.pending.filter { it.operationId != null && it.error == null }) {
            try {
                val j = io {
                    api(p.home).call("/v1/home/requests/" + encoded(p.operationId!!)).json
                }
                val response = j.optJSONObject("response")
                if (response != null && response.getInt("status") < 400)
                    persist { s -> s.copy(pending = s.pending.filterNot { it.id == p.id }) }
                else if (response != null || j.optString("status") == "canceled")
                    persist { s ->
                        s.copy(
                            pending =
                                s.pending.map {
                                    if (it.id == p.id)
                                        it.copy(
                                            error =
                                                "Устройство не выполнило запрос. Проверьте результат перед повтором."
                                        )
                                    else it
                                }
                        )
                    }
            } catch (e: Exception) {
                if (e is CancellationException) throw e
            }
        }
    }

    fun cancel(ref: ChatRef, message: Message) {
        launchAction {
            io {
                api(ref.home)
                    .action(
                        "/v1/conversations/" +
                            encoded(message.conversationId) +
                            "/messages/" +
                            encoded(message.id) +
                            "/cancel"
                    )
            }
            refreshChat(ref)
        }
    }

    suspend fun models(ref: ChatRef): JSONObject {
        val conversation =
            _state.value.chats[ref.key]?.conversation
                ?: throw HomeFailure(409, "Сначала откройте чат.")
        if (_state.value.homes[ref.home]?.health?.optInt("conversationModelsVersion") != 1)
            throw HomeFailure(
                409,
                "Обновите OpenStrudel на этом устройстве для выбора модели чата.",
            )
        return io {
            api(ref.home).call("/v1/settings/models?conversationId=" + encoded(conversation)).json
        }
    }

    suspend fun saveModel(ref: ChatRef, selection: JSONObject) {
        val conversation =
            _state.value.chats[ref.key]?.conversation
                ?: throw HomeFailure(409, "Сначала откройте чат.")
        if (_state.value.homes[ref.home]?.health?.optInt("conversationModelsVersion") != 1)
            throw HomeFailure(409, "Обновите OpenStrudel на этом устройстве.")
        io {
            api(ref.home)
                .action(
                    "/v1/settings/models?conversationId=" + encoded(conversation),
                    body = selection,
                )
        }
        refreshChat(ref)
    }

    suspend fun services(ref: ChatRef): JSONObject = io {
        api(ref.home).call("/v1/connections?conversationId=" + encoded(conversation(ref))).json
    }

    suspend fun schedules(ref: ChatRef): JSONObject = io {
        api(ref.home).call("/v1/conversations/" + encoded(conversation(ref)) + "/schedules").json
    }

    suspend fun toggleSchedule(ref: ChatRef, schedule: JSONObject) {
        io {
            api(ref.home)
                .action(
                    "/v1/conversations/" + encoded(conversation(ref)) + "/schedules",
                    body =
                        JSONObject(schedule.toString())
                            .put("enabled", !schedule.getBoolean("enabled")),
                )
        }
    }

    suspend fun extensions(ref: ChatRef): JSONObject = io {
        api(ref.home).call("/v1/extensions?conversationId=" + encoded(conversation(ref))).json
    }

    suspend fun changeExtension(ref: ChatRef, id: String, enabled: Boolean) {
        io {
            api(ref.home)
                .action(
                    "/v1/extensions/change",
                    body =
                        json(
                            "id" to id,
                            "enabled" to enabled,
                            "conversationId" to conversation(ref),
                        ),
                )
        }
    }

    suspend fun addMcp(ref: ChatRef, name: String, url: String, token: String) {
        io {
            api(ref.home)
                .action(
                    "/v1/extensions/mcp",
                    body =
                        json(
                            "name" to name,
                            "url" to url,
                            "token" to token,
                            "conversationId" to conversation(ref),
                        ),
                )
        }
    }

    private fun skillPayload(ref: ChatRef, file: LocalFile): JSONObject {
        if (!file.name.equals("SKILL.md", true) || file.size > 256 * 1024)
            throw HomeFailure(400, "Выберите файл SKILL.md размером до 256 КБ.")
        return json(
            "conversationId" to conversation(ref),
            "files" to
                JSONArray(
                    listOf(
                        json(
                            "path" to "SKILL.md",
                            "contentBase64" to
                                Base64.getEncoder().encodeToString(File(file.path).readBytes()),
                            "executable" to false,
                        )
                    )
                ),
        )
    }

    suspend fun previewSkill(ref: ChatRef, file: LocalFile): JSONObject = io {
        api(ref.home).action("/v1/extensions/preview", body = skillPayload(ref, file))
    }

    suspend fun installSkill(ref: ChatRef, file: LocalFile, preview: JSONObject) {
        io {
            api(ref.home)
                .action(
                    "/v1/extensions/install",
                    body =
                        skillPayload(ref, file)
                            .put("digest", preview.getString("digest"))
                            .put("replaces", preview.opt("replaces") ?: JSONObject.NULL),
                )
        }
    }

    private fun conversation(ref: ChatRef) =
        _state.value.chats[ref.key]?.conversation ?: throw HomeFailure(409, "Сначала откройте чат.")

    suspend fun connectService(ref: ChatRef, id: String): String? {
        val chat = conversation(ref)
        val result = io {
            api(ref.home)
                .action(
                    "/v1/connections/connect",
                    body = json("id" to id, "conversationId" to chat, "callback" to "app"),
                )
        }
        result.string("signInId")?.let { id ->
            if (!Regex("[a-f0-9]{48}").matches(id))
                throw HomeFailure(400, "Не удалось начать вход. Попробуйте ещё раз.")
            persist { it.copy(oauth = listOf(ref.home, chat, id)) }
        }
        return result.string("url")
    }

    private fun completeOAuth(url: String) {
        launchAction {
            val saved =
                _state.value.stored.oauth
                    ?: throw HomeFailure(409, "Вход истёк. Подключите сервис ещё раз.")
            val flow = Triple(saved[0], saved[1], saved[2])
            val uri = Uri.parse(url)
            require(
                uri.scheme == "openstrudel" &&
                    uri.host == "oauth" &&
                    uri.userInfo == null &&
                    uri.fragment == null &&
                    uri.port == -1 &&
                    (uri.path == "/service/" + flow.third ||
                        uri.path?.startsWith("/service/" + flow.third + "/") == true)
            )
            io {
                api(flow.first)
                    .action(
                        "/v1/connections/oauth/" +
                            encoded(flow.third) +
                            "?conversationId=" +
                            encoded(flow.second),
                        body = json("url" to url),
                    )
            }
            persist { it.copy(oauth = null) }
            notice("Сервис подключён.")
        }
    }

    suspend fun importFile(uri: Uri): LocalFile = io {
        val resolver = getApplication<Application>().contentResolver
        var name = "Файл"
        resolver
            .query(
                uri,
                arrayOf(OpenableColumns.DISPLAY_NAME, OpenableColumns.SIZE),
                null,
                null,
                null,
            )
            ?.use { c ->
                if (c.moveToFirst()) {
                    name = c.getString(0)
                    require(c.isNull(1) || c.getLong(1) <= 20L * 1024 * 1024) {
                        "Файл должен быть не больше 20 МБ."
                    }
                }
            }
        val folder =
            File(getApplication<Application>().noBackupFilesDir, "draft-files").apply { mkdirs() }
        val id = UUID.randomUUID().toString()
        val target = File(folder, id)
        try {
            resolver.openInputStream(uri)!!.use { input ->
                target.outputStream().use { out ->
                    val buffer = ByteArray(8192)
                    var total = 0L
                    while (true) {
                        val n = input.read(buffer)
                        if (n < 0) break
                        total += n
                        require(total <= 20L * 1024 * 1024) { "Файл должен быть не больше 20 МБ." }
                        out.write(buffer, 0, n)
                    }
                }
            }
        } catch (e: Exception) {
            target.delete()
            throw e
        }
        LocalFile(
            id,
            name.take(200),
            resolver.getType(uri) ?: "application/octet-stream",
            target.path,
            target.length(),
        )
    }

    fun addFiles(ref: ChatRef, uris: List<Uri>) {
        launchAction {
            val available = 10 - (_state.value.drafts[ref.key]?.files?.size ?: 0)
            if (available <= 0)
                throw HomeFailure(400, "В одном сообщении можно отправить до 10 файлов.")
            val files = uris.take(available).map { importFile(it) }
            val draft = _state.value.drafts[ref.key] ?: Draft()
            saveDraft(ref, draft.copy(files = (draft.files + files).take(10)))
            if (uris.size > available)
                notice(
                    "Добавлены первые $available файлов. Остальные можно отправить следующим сообщением."
                )
        }
    }

    private fun pruneDraftFiles(saved: StoredState) {
        val keep =
            (saved.drafts.values.flatMap { it.files + listOfNotNull(it.recording) } +
                    saved.pending.flatMap { it.files })
                .map { it.path }
                .toSet()
        val folder = File(getApplication<Application>().noBackupFilesDir, "draft-files")
        val cutoff = System.currentTimeMillis() - 24L * 60 * 60 * 1000
        folder
            .listFiles()
            ?.filter {
                it.isFile &&
                    it.canonicalFile.parentFile == folder.canonicalFile &&
                    it.lastModified() < cutoff &&
                    it.path !in keep
            }
            ?.forEach { it.delete() }
    }

    suspend fun attachment(home: String, file: Attachment): File = io {
        val folder = File(getApplication<Application>().cacheDir, "opened").apply { mkdirs() }
        val target =
            File(
                folder,
                home.replace(Regex("[^A-Za-z0-9-]"), "_") +
                    "-" +
                    file.id.replace(Regex("[^A-Za-z0-9-]"), "_") +
                    "-" +
                    file.name.replace(Regex("[^\\p{L}\\p{N}._ -]"), "_").take(120),
            )
        if (!target.exists() || target.length() != file.size) {
            val bytes = api(home).file(file.id)
            val temporary = File(folder, UUID.randomUUID().toString() + ".tmp")
            try {
                temporary.writeBytes(bytes)
                check(temporary.renameTo(target))
            } finally {
                temporary.delete()
            }
            // Downloads are reproducible; keep recently opened files and bound older copies.
            var total = folder.listFiles()?.sumOf { it.length() } ?: 0
            val cutoff = System.currentTimeMillis() - 60L * 60 * 1000
            folder
                .listFiles()
                ?.filter { it.isFile && it != target && it.lastModified() < cutoff }
                ?.sortedBy { it.lastModified() }
                ?.forEach {
                    if (
                        total > 128L * 1024 * 1024 ||
                            it.lastModified() <
                                System.currentTimeMillis() - 7L * 24 * 60 * 60 * 1000
                    ) {
                        val size = it.length()
                        if (it.delete()) total -= size
                    }
                }
        }
        target
    }

    fun saveRecording(ref: ChatRef, file: LocalFile) {
        val draft = _state.value.drafts[ref.key] ?: Draft()
        saveDraft(ref, draft.copy(recording = file))
    }

    fun transcribe(ref: ChatRef) {
        if (ref.key in _state.value.transcribing) return
        val recording = _state.value.drafts[ref.key]?.recording ?: return
        val query =
            _state.value.chats[ref.key]?.conversation?.let { "?conversationId=" + encoded(it) }
                ?: _state.value.homes[ref.home]
                    ?.employees
                    ?.firstOrNull { it.id == ref.employee }
                    ?.deviceId
                    ?.let { "?deviceId=" + encoded(it) }
                ?: ""
        _state.update { it.copy(transcribing = it.transcribing + ref.key) }
        launchAction {
            try {
                val text = io {
                    val bytes = File(recording.path).readBytes()
                    api(ref.home)
                        .action(
                            "/v1/speech/transcribe" + query,
                            body =
                                json(
                                    "name" to "dictation.m4a",
                                    "contentBase64" to Base64.getEncoder().encodeToString(bytes),
                                ),
                        )
                        .getString("text")
                }
                if (connection(ref.home) == null) return@launchAction
                val draft = _state.value.drafts[ref.key] ?: Draft()
                if (draft.recording?.id == recording.id)
                    saveDraft(
                        ref,
                        draft.copy(
                            text =
                                listOf(draft.text, text)
                                    .filter { it.isNotBlank() }
                                    .joinToString("\n"),
                            recording = null,
                        ),
                    )
            } finally {
                _state.update { it.copy(transcribing = it.transcribing - ref.key) }
            }
        }
    }

    override fun onCleared() {
        clients.values.forEach { it.close() }
        super.onCleared()
    }
}
