package app.openstrudel

import org.junit.Assert.*
import org.junit.Test

class SendModeTest {
    @Test
    fun sendsOnlyTheModesTheHomeAccepts() {
        assertEquals("steer", serverSendMode("steer"))
        assertEquals("queue", serverSendMode("queue"))
        // Older drafts may hold "interrupt", which the Home rejects; they go out as ordinary messages.
        assertNull(serverSendMode("interrupt"))
        assertEquals(listOf("steer", "queue"), sendModes.map { it.first })
    }
}
