package app.openstrudel

import android.content.Context
import android.content.Intent
import android.net.Uri
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createEmptyComposeRule
import androidx.test.core.app.ActivityScenario
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import java.io.File
import java.security.MessageDigest
import java.util.UUID
import java.util.concurrent.CopyOnWriteArrayList
import java.util.concurrent.atomic.AtomicInteger
import kotlinx.coroutines.runBlocking
import okhttp3.mockwebserver.Dispatcher
import okhttp3.mockwebserver.MockResponse
import okhttp3.mockwebserver.MockWebServer
import okhttp3.mockwebserver.RecordedRequest
import okhttp3.tls.HandshakeCertificates
import okhttp3.tls.HeldCertificate
import org.json.JSONArray
import org.json.JSONObject
import org.junit.After
import org.junit.Assert.*
import org.junit.Before
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

/** Runs on a real phone against isolated TLS Homes, with no model or company mutations. */
@RunWith(AndroidJUnit4::class)
class CompanionTest {
    @get:Rule val compose = createEmptyComposeRule()
    private val context = ApplicationProvider.getApplicationContext<Context>()
    private lateinit var previous: StoredState
    private val fixtures = mutableListOf<Fixture>()
    private var scenario: ActivityScenario<MainActivity>? = null
    private lateinit var model: HomeViewModel

    @Before
    fun prepare() {
        previous = SecureState(context).read()
        SecureState(context).write(StoredState())
    }

    @After
    fun cleanup() {
        scenario?.close()
        fixtures.forEach { it.server.shutdown() }
        SecureState(context).write(previous)
    }

    private fun fixture(name: String) = Fixture(name).also { fixtures += it }

    private fun launch(state: StoredState = StoredState(), link: String? = null) {
        SecureState(context).write(state)
        val intent =
            Intent(context, MainActivity::class.java).apply {
                if (link != null) {
                    action = Intent.ACTION_VIEW
                    data = Uri.parse(link)
                }
            }
        scenario = ActivityScenario.launch(intent)
        scenario!!.onActivity { model = it.model }
        compose.waitUntil(10000) { model.state.value.loaded }
    }

    private fun connected(id: String) {
        compose.waitUntil(15000) { model.state.value.homes[id]?.online == true }
    }

    @Test
    fun invitationRequiresReviewAndSavesOnlyAfterPairing() {
        val home = fixture("Android QA Home")
        launch(link = home.link)
        compose.onNodeWithTag("confirm-pair").assertExists()
        assertEquals(0, home.pairs.get())
        compose.onNodeWithTag("confirm-pair").performClick()
        compose.waitUntil(15000) { model.state.value.stored.connections.size == 1 }
        assertEquals(1, home.pairs.get())
        val saved = SecureState(context).read().connections.single()
        assertEquals(home.credential, saved.token)
        assertNull(SecureState(context).read().pairing)
        val bytes = File(context.noBackupFilesDir, "connections-v1").readBytes()
        assertFalse(String(bytes, Charsets.ISO_8859_1).contains(home.credential))
        scenario!!.recreate()
        scenario!!.onActivity { model = it.model }
        compose.waitUntil(10000) { model.state.value.stored.connections.size == 1 }
        assertEquals(saved, model.state.value.stored.connections.single())
    }

    @Test
    fun wholeRowOpensChatDraftSurvivesRotationAndSendIsNotDuplicated() {
        val home = fixture("Fixture A")
        launch(StoredState(connections = listOf(home.connection)))
        connected(home.connection.id)
        val row = compose.onNodeWithTag("employee-writer")
        val bounds = row.fetchSemanticsNode().boundsInRoot
        row.performTouchInput { click(Offset(bounds.width - 8f, bounds.height / 2f)) }
        compose.onNodeWithTag("composer").performTextInput("Новый черновик")
        scenario!!.onActivity { runBlocking { model.flushDrafts() } }
        scenario!!.recreate()
        scenario!!.onActivity { model = it.model }
        compose.onNodeWithTag("composer").assertTextContains("Новый черновик")
        compose.waitUntil(10000) { model.state.value.chats.values.any { it.loaded } }
        val ref = ChatRef(home.connection.id, "writer")
        scenario!!.onActivity {
            model.send(ref)
            model.send(ref)
        }
        compose.waitUntil(15000) {
            home.sends.size == 1 && model.state.value.stored.pending.isEmpty()
        }
        assertEquals(1, home.sends.size)
        assertEquals("steer", home.sends.single().getString("mode"))
        assertTrue(model.state.value.drafts[ref.key]?.text.isNullOrEmpty())
    }

    @Test
    fun delayedCatalogueCannotResurrectDisconnectedHome() {
        val first = fixture("Fixture A")
        val second = fixture("Fixture B")
        launch(StoredState(connections = listOf(first.connection, second.connection)))
        connected(first.connection.id)
        connected(second.connection.id)
        val reads = first.profileReads.get()
        first.slowProfiles = true
        scenario!!.onActivity { model.refreshNow() }
        compose.waitUntil(5000) { first.profileReads.get() > reads }
        scenario!!.onActivity { model.removeHome(first.connection.id) }
        compose.waitUntil(10000) { model.state.value.stored.connections.size == 1 }
        Thread.sleep(2200)
        assertEquals(
            listOf(second.connection.id),
            SecureState(context).read().connections.map { it.id },
        )
        assertFalse(model.state.value.homes.containsKey(first.connection.id))
        scenario!!.close()
        scenario = null
        launch(SecureState(context).read())
        connected(second.connection.id)
        assertEquals(
            listOf(second.connection.id),
            model.state.value.stored.connections.map { it.id },
        )
    }

    @Test
    fun transcriptionIsEditableAndNeverAutoSends() {
        val home = fixture("Speech fixture")
        launch(StoredState(connections = listOf(home.connection)))
        connected(home.connection.id)
        compose.onNodeWithTag("employee-writer").performClick()
        compose.waitUntil(10000) { model.state.value.chats.values.any { it.loaded } }
        val ref = ChatRef(home.connection.id, "writer")
        val audio =
            File(context.noBackupFilesDir, "fixture-audio.m4a").apply {
                writeBytes(byteArrayOf(0, 1, 2, 3))
            }
        try {
            scenario!!.onActivity {
                model.saveRecording(
                    ref,
                    LocalFile(
                        name = "voice.m4a",
                        mimeType = "audio/mp4",
                        path = audio.path,
                        size = audio.length(),
                    ),
                )
                model.transcribe(ref)
            }
            compose.waitUntil(10000) {
                model.state.value.drafts[ref.key]?.text == "Распознанный текст"
            }
            compose.onNodeWithTag("composer").performTextInput(" с правкой")
            assertEquals(0, home.sends.size)
            assertEquals("chat", home.speechChat)
        } finally {
            audio.delete()
        }
    }

    @Test
    fun removedEmployeeAndChatModelSelectionStayScoped() {
        val home = fixture("Models fixture")
        launch(StoredState(connections = listOf(home.connection)))
        connected(home.connection.id)
        compose.onNodeWithTag("employee-writer").performClick()
        compose.waitUntil(10000) { model.state.value.chats.values.any { it.loaded } }
        val ref = ChatRef(home.connection.id, "writer")
        runBlocking {
            model.saveModel(
                ref,
                json(
                    "provider" to "codex",
                    "model" to "supported-model",
                    "serviceTier" to null,
                    "reasoningEffort" to "high",
                ),
            )
        }
        assertEquals("chat", home.modelChat)
        assertEquals("supported-model", home.modelSelection!!.getString("model"))
        scenario!!.onActivity { model.hide(ref, true) }
        compose.waitUntil(5000) { ref.key in model.state.value.stored.hidden }
        assertTrue(ref.key in SecureState(context).read().hidden)
    }

    @Test
    fun newAnswerStaysVisibleWhenReadingTheLatestMessage() {
        val home = fixture("Timeline fixture")
        fun message(id: String, text: String, direction: String) =
            json(
                "id" to id,
                "conversationId" to "chat",
                "text" to text,
                "direction" to direction,
                "channel" to "api",
                "status" to "completed",
                "createdAt" to "2026-10-17T12:00:00Z",
            )
        home.messages += message("question", "A long question. ".repeat(150), "inbound")
        launch(StoredState(connections = listOf(home.connection)))
        connected(home.connection.id)
        compose.onNodeWithTag("employee-writer").performClick()
        compose.waitUntil(10000) { model.state.value.chats.values.any { it.loaded } }
        home.messages += message("answer", "A short answer.", "outbound")
        runBlocking { model.refreshChat(ChatRef(home.connection.id, "writer")) }
        compose.onNodeWithTag("message-answer").assertIsDisplayed()
    }

    @Test
    fun deletionRequiresConfirmationAndKeepsOtherHomeIntact() {
        val first = fixture("First Home")
        val second = fixture("Second Home")
        launch(StoredState(connections = listOf(first.connection, second.connection)))
        connected(first.connection.id)
        connected(second.connection.id)
        compose.waitUntil(5000) { model.state.value.homes[first.connection.id]?.canManage == true }
        fun requestDelete() {
            compose.onAllNodesWithTag("employee-writer")[0].performTouchInput { longClick() }
            compose.onNodeWithText("Удалить…").performClick()
            compose.onNodeWithText("Удалить «Редактор QA»?").assertExists()
        }
        requestDelete()
        assertEquals(0, first.deletes.get())
        compose.onNodeWithText("Отмена").performClick()
        assertEquals(0, first.deletes.get())
        requestDelete()
        compose.onNodeWithText("Удалить", useUnmergedTree = true).performClick()
        compose.waitUntil(10000) {
            model.state.value.homes[first.connection.id]?.employees?.isEmpty() == true
        }
        assertEquals(1, first.deletes.get())
        assertEquals(0, second.deletes.get())
        assertEquals(
            "writer",
            model.state.value.homes[second.connection.id]!!.employees.single().id,
        )
    }

    @Test
    fun completedAndUncertainRemindersCannotBeSilentlyEnabledAgain() {
        val home = fixture("Reminder fixture")
        for ((id, status) in listOf("done" to "completed", "unknown" to "uncertain")) {
            home.schedules += json("id" to id, "conversationId" to "chat", "name" to id,
                "prompt" to "Remind", "cron" to "@once 2030-01-15T09:30:00+03:00",
                "timezone" to "Europe/Moscow", "enabled" to false,
                "nextRunAt" to "2030-01-15T06:30:00.000Z", "lastRunStatus" to status)
        }
        launch(StoredState(connections = listOf(home.connection)))
        connected(home.connection.id)
        compose.onNodeWithTag("employee-writer").performClick()
        compose.waitUntil(10000) { model.state.value.chats.values.any { it.loaded } }
        compose.onNodeWithContentDescription("Действия чата").performClick()
        compose.onNodeWithText("Расписание").performClick()
        compose.waitUntil(10000) { compose.onAllNodesWithText("Выполнено", substring = true).fetchSemanticsNodes().isNotEmpty() }
        compose.onNodeWithText("Проверьте результат", substring = true).assertExists()
        compose.onAllNodes(isToggleable()).assertCountEquals(0)
    }

    private class Fixture(name: String) {
        val server = MockWebServer()
        val pairs = AtomicInteger()
        val profileReads = AtomicInteger()
        val deletes = AtomicInteger()
        val sends = CopyOnWriteArrayList<JSONObject>()
        val messages = CopyOnWriteArrayList<JSONObject>()
        val schedules = CopyOnWriteArrayList<JSONObject>()
        @Volatile var slowProfiles = false
        @Volatile var speechChat: String? = null
        @Volatile var modelChat: String? = null
        @Volatile var modelSelection: JSONObject? = null
        val credential = "c".repeat(64)
        val invite = "a".repeat(64)
        val certificate = HeldCertificate.Builder().commonName("Fixture Home").build()
        val pin =
            MessageDigest.getInstance("SHA-256")
                .digest(certificate.certificate.encoded)
                .joinToString("") { "%02x".format(it.toInt() and 255) }
        val connection: Connection
        val link: String

        init {
            server.useHttps(
                HandshakeCertificates.Builder()
                    .heldCertificate(certificate)
                    .build()
                    .sslSocketFactory(),
                false,
            )
            server.dispatcher =
                object : Dispatcher() {
                    override fun dispatch(request: RecordedRequest): MockResponse {
                        val path = request.requestUrl!!.encodedPath
                        if (path == "/pair") {
                            pairs.incrementAndGet()
                            return ok(json("token" to credential))
                        }
                        if (request.getHeader("Authorization") != "Bearer $credential")
                            return MockResponse().setResponseCode(401).setBody("{}")
                        return when {
                            path == "/health" ->
                                ok(
                                    json(
                                        "conversationModelsVersion" to 1,
                                        "turnControlVersion" to 1,
                                        "employeeTimelineVersion" to 1,
                                        "speechVersion" to 1,
                                    )
                                )
                            path == "/v1/account" -> ok(json("canManage" to true))
                            path == "/v1/profiles" -> {
                                profileReads.incrementAndGet()
                                if (slowProfiles) Thread.sleep(1800)
                                ok(
                                    json(
                                        "profiles" to
                                            if (deletes.get() > 0) JSONArray()
                                            else
                                                JSONArray(
                                                    listOf(
                                                        json(
                                                            "id" to "writer",
                                                            "name" to "Редактор QA",
                                                            "instructions" to "Fixture",
                                                            "appearance" to json("kind" to "coil"),
                                                        )
                                                    )
                                                )
                                    )
                                )
                            }
                            path == "/v1/profiles/writer" && request.method == "DELETE" -> {
                                deletes.incrementAndGet()
                                ok(JSONObject())
                            }
                            path == "/auth/device/logout" -> ok(JSONObject())
                            path.endsWith("/conversation") ->
                                ok(
                                    json(
                                        "conversation" to json("id" to "chat"),
                                        "messages" to JSONArray(messages),
                                        "pagination" to JSONObject(),
                                    )
                                )
                            path == "/v1/messages" -> {
                                sends += JSONObject(request.body.readUtf8())
                                ok(json("messageId" to "accepted", "conversationId" to "chat"))
                            }
                            path == "/v1/conversations/chat/schedules" -> ok(json("schedules" to JSONArray(schedules), "runs" to JSONArray()))
                            path == "/v1/speech/transcribe" -> {
                                speechChat = request.requestUrl!!.queryParameter("conversationId")
                                ok(json("text" to "Распознанный текст"))
                            }
                            path == "/v1/settings/models" -> {
                                modelChat = request.requestUrl!!.queryParameter("conversationId")
                                if (request.method == "POST")
                                    modelSelection = JSONObject(request.body.readUtf8())
                                ok(
                                    json(
                                        "models" to JSONArray(),
                                        "selection" to (modelSelection ?: JSONObject()),
                                        "canManage" to true,
                                    )
                                )
                            }
                            else ->
                                MockResponse()
                                    .setResponseCode(404)
                                    .setBody("{\"error\":\"Not found\"}")
                        }
                    }
                }
            server.start()
            connection =
                Connection(
                    "fixture-" + UUID.randomUUID().toString(),
                    server.url("/").toString().removeSuffix("/"),
                    credential,
                    pin,
                    name,
                )
            link =
                "openstrudel://connect?host=localhost&port=${server.port}&key=$invite&pin=$pin&name=" +
                    encoded(name)
        }

        private fun ok(json: JSONObject) =
            MockResponse().setHeader("Content-Type", "application/json").setBody(json.toString())
    }
}
