package app.openstrudel

import java.util.UUID
import org.junit.Assert.*
import org.junit.Test

class InvitationTest {
    private val key = "a".repeat(64)
    private val pin = "b".repeat(64)
    private val link =
        "openstrudel://connect?host=home.example.com&port=9443&key=$key&pin=$pin&name=Wolf+Wolf"

    @Test
    fun invitationAndWebQrShareTheSameTrust() {
        val direct = Invitation.parse(link)
        assertEquals(
            direct,
            Invitation.parse("https://waiwai.is/openstrudel/connect.html#" + encoded(link)),
        )
        assertEquals("Wolf Wolf", direct.name)
        assertEquals("https://home.example.com:9443", direct.baseUrl)
        assertEquals("spki:$key", Invitation.parse(link + "&keyPin=$key").pin)
        assertFalse(direct.toString().contains(key))
    }

    @Test
    fun misleadingLinksNeverBecomeInvitations() {
        val invalid =
            listOf(
                link + "&host=evil.example",
                link + "&key=$pin",
                link + "#fragment",
                link.replace("connect?", "connect/path?"),
                link.replace("connect?", "owner@connect?"),
                link.replace("port=9443", "port=0"),
                link.replace("port=9443", "port=65536"),
                link.replace("home.example.com", "home.example.com%2Fpath"),
                link.replace("home.example.com", "home..example"),
                link.replace("home.example.com", "localhost."),
                link.replace("key=$key", "key=short"),
                link + "&keyPin=invalid",
                "https://evil.example/openstrudel/connect.html#" + encoded(link),
                "https://waiwai.is/openstrudel/connect.html?tracking=1#" + encoded(link),
                "https://owner@waiwai.is/openstrudel/connect.html#" + encoded(link),
                "https://waiwai.is:8443/openstrudel/connect.html#" + encoded(link),
                "openstrudel://oauth/service/foo",
                "x".repeat(4097),
            )
        for (value in invalid) assertTrue(
            "Accepted misleading invitation",
            runCatching { Invitation.parse(value) }.isFailure,
        )
    }

    @Test
    fun durableStateRetainsRecoveryIdentifiers() {
        val c = Connection("home", "https://home.example.com:9443", key, pin, "Wolf")
        val file =
            LocalFile(
                name = "voice.m4a",
                mimeType = "audio/mp4",
                path = "/private/draft",
                size = 123,
            )
        val outgoing =
            PendingSend(
                home = c.id,
                employee = "writer",
                conversation = "chat",
                text = "Hello",
                mode = "queue",
                files = listOf(file),
                operationId = "operation",
            )
        val state =
            StoredState(
                connections = listOf(c),
                drafts = mapOf("home/writer" to Draft("Editable", recording = file)),
                hidden = setOf("home/hidden"),
                pending = listOf(outgoing),
                pairing = PairAttempt(c, UUID.randomUUID().toString()),
                oauth = listOf("home", "chat", "sign-in"),
            )
        assertEquals(state, StoredState.from(state.toJson()))
        assertFalse(c.toString().contains(key))
    }

    private fun message(id: String, text: String = id, status: String = "complete") =
        Message(
            id,
            "chat",
            text,
            false,
            "2026-10-17T10:00:00Z",
            status,
            "api",
            null,
            null,
            null,
            null,
            emptyList(),
        )

    @Test
    fun pagingKeepsLiveUpdatesAndDoesNotDuplicateMessages() {
        val initial = listOf(message("2"), message("3", "thinking", "running"))
        val older = mergeMessages(initial, listOf(message("1"), message("2")), prepend = true)
        val refreshed =
            mergeMessages(
                older,
                listOf(message("4")),
                updates = listOf(message("3", "answer")),
                removed = setOf("2"),
            )
        assertEquals(listOf("1", "3", "4"), refreshed.map { it.id })
        assertEquals("answer", refreshed[1].text)
        assertFalse(refreshed[1].working)
    }
}
