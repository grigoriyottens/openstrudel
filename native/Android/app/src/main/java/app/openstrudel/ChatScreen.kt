@file:OptIn(androidx.compose.material3.ExperimentalMaterial3Api::class)

package app.openstrudel

import android.Manifest
import android.content.Intent
import android.content.pm.PackageManager
import android.widget.TextView
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.selection.SelectionContainer
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.rounded.Send
import androidx.compose.material.icons.rounded.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.toArgb
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.viewinterop.AndroidView
import androidx.core.content.ContextCompat
import androidx.core.content.FileProvider
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleEventObserver
import androidx.lifecycle.compose.LocalLifecycleOwner
import androidx.navigation3.runtime.NavKey
import coil3.compose.AsyncImage
import io.noties.markwon.Markwon
import io.noties.markwon.ext.tables.TablePlugin
import java.io.File
import java.time.Instant
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

@Composable
fun ChatScreen(
    model: HomeViewModel,
    state: AppState,
    ref: ChatRef,
    back: () -> Unit,
    open: (NavKey) -> Unit,
) {
    val person = employee(state, ref)
    val chat = state.chats[ref.key] ?: ChatView()
    val home = state.homes[ref.home]
    val connection = state.stored.connections.firstOrNull { it.id == ref.home }
    var menu by remember { mutableStateOf(false) }
    val list = rememberLazyListState()
    val scope = rememberCoroutineScope()
    val pending = state.stored.pending.filter { it.home == ref.home && it.employee == ref.employee }
    val modelName = chat.effective?.string("model")
    var followLatest by remember(ref) { mutableStateOf(true) }
    val showScrollDown by remember {
        derivedStateOf { list.firstVisibleItemIndex > 0 || list.firstVisibleItemScrollOffset > 32 }
    }
    LaunchedEffect(list) {
        snapshotFlow {
            Triple(
                list.isScrollInProgress,
                list.firstVisibleItemIndex,
                list.firstVisibleItemScrollOffset,
            )
        }
            .collect { (scrolling, index, offset) ->
                if (scrolling) followLatest = index == 0 && offset < 32
            }
    }
    LaunchedEffect(chat.messages.lastOrNull()?.id, pending.lastOrNull()?.id) {
        if (followLatest) list.scrollToItem(0)
    }
    Scaffold(
        topBar = {
            TopAppBar(
                title = {
                    Row(
                        verticalAlignment = Alignment.CenterVertically,
                        modifier =
                            Modifier.clickable(enabled = ref.employee != "main") {
                                open(EmployeeRoute(ref.home, ref.employee))
                            },
                    ) {
                        Avatar(person?.character ?: "coil", ref.employee == "main", 36)
                        Column(Modifier.padding(start = 10.dp)) {
                            Text(
                                person?.name ?: "Сотрудник",
                                maxLines = 1,
                                overflow = TextOverflow.Ellipsis,
                                style = MaterialTheme.typography.titleMedium,
                            )
                            Text(
                                connection?.name ?: "Устройство отключено",
                                maxLines = 1,
                                overflow = TextOverflow.Ellipsis,
                                style = MaterialTheme.typography.labelSmall,
                                color = MaterialTheme.colorScheme.onSurfaceVariant,
                            )
                        }
                    }
                },
                navigationIcon = { BackButton(back) },
                actions = {
                    Box {
                        IconButton(onClick = { menu = true }) {
                            Icon(Icons.Rounded.MoreVert, "Действия чата")
                        }
                        DropdownMenu(menu, { menu = false }) {
                            DropdownMenuItem(
                                text = { Text("Сервисы и навыки") },
                                onClick = {
                                    menu = false
                                    open(ServicesRoute(ref.home, ref.employee))
                                },
                            )
                            DropdownMenuItem(
                                text = { Text("Расписание") },
                                onClick = {
                                    menu = false
                                    open(SchedulesRoute(ref.home, ref.employee))
                                },
                            )
                            if (ref.employee != "main")
                                DropdownMenuItem(
                                    text = { Text("Настроить сотрудника") },
                                    onClick = {
                                        menu = false
                                        open(EmployeeRoute(ref.home, ref.employee))
                                    },
                                )
                            DropdownMenuItem(
                                text = { Text("Обновить") },
                                onClick = {
                                    menu = false
                                    model.refreshNow()
                                },
                            )
                        }
                    }
                },
            )
        },
        contentWindowInsets = WindowInsets.safeDrawing,
    ) { insets ->
        Column(Modifier.fillMaxSize().padding(insets).consumeWindowInsets(insets)) {
            if (chat.error != null || connection == null)
                TextButton(onClick = model::refreshNow, modifier = Modifier.fillMaxWidth()) {
                    Text(
                        chat.error ?: "Устройство отключено. Вернитесь к списку сотрудников.",
                        maxLines = 3,
                    )
                }
            if (!chat.loaded && chat.loading) LinearProgressIndicator(Modifier.fillMaxWidth())
            Box(Modifier.weight(1f)) {
                LazyColumn(
                    state = list,
                    reverseLayout = true,
                    modifier = Modifier.fillMaxSize().testTag("messages"),
                    contentPadding = PaddingValues(horizontal = 16.dp, vertical = 12.dp),
                    verticalArrangement = Arrangement.spacedBy(12.dp),
                ) {
                    items(pending.asReversed(), key = { "pending:" + it.id }) { p ->
                        Column(Modifier.fillMaxWidth(), horizontalAlignment = Alignment.End) {
                            Surface(
                                shape = RoundedCornerShape(20.dp),
                                color = MaterialTheme.colorScheme.secondaryContainer,
                            ) {
                                Column(Modifier.padding(14.dp).widthIn(max = 480.dp)) {
                                    if (p.text.isNotEmpty()) Text(p.text)
                                    p.files.forEach {
                                        Text(it.name, style = MaterialTheme.typography.bodySmall)
                                    }
                                    Text(
                                        p.error ?: "Отправляем…",
                                        style = MaterialTheme.typography.bodySmall,
                                        color =
                                            if (p.error != null) MaterialTheme.colorScheme.error
                                            else MaterialTheme.colorScheme.onSurfaceVariant,
                                    )
                                    if (p.error != null)
                                        TextButton(onClick = { model.retrySend(p.id) }) {
                                            Text("Повторить")
                                        }
                                }
                            }
                        }
                    }
                    items(chat.messages.asReversed(), key = { it.id }) { message ->
                        MessageBubble(model, ref.home, message) { model.cancel(ref, message) }
                    }
                    if (chat.older != null)
                        item("earlier") {
                            TextButton(
                                enabled = !chat.loading,
                                onClick = { model.earlier(ref) },
                                modifier = Modifier.fillMaxWidth(),
                            ) {
                                Text(if (chat.loading) "Загружаем…" else "Ранние сообщения")
                            }
                        }
                    if (chat.loaded && chat.messages.isEmpty() && pending.isEmpty())
                        item("empty") {
                            Column(
                                Modifier.fillParentMaxHeight().fillMaxWidth(),
                                horizontalAlignment = Alignment.CenterHorizontally,
                                verticalArrangement = Arrangement.Center,
                            ) {
                                Avatar(person?.character ?: "main", ref.employee == "main", 88)
                                Text(
                                    "Напишите, что нужно",
                                    style = MaterialTheme.typography.headlineSmall,
                                    modifier = Modifier.padding(top = 20.dp),
                                )
                            }
                        }
                }
                if (showScrollDown)
                    FilledTonalIconButton(
                        onClick = {
                            followLatest = true
                            scope.launch { list.animateScrollToItem(0) }
                        },
                        modifier = Modifier.align(Alignment.BottomEnd).padding(16.dp),
                    ) {
                        Icon(Icons.Rounded.KeyboardArrowDown, "К последнему сообщению")
                    }
            }
            Composer(
                model,
                state,
                ref,
                enabled = connection != null,
                modelName = modelName,
                onModel = { open(ModelsRoute(ref.home, ref.employee)) },
                modelAvailable = home?.health?.optInt("conversationModelsVersion") == 1,
                onSent = {
                    followLatest = true
                    scope.launch { list.animateScrollToItem(0) }
                },
            )
        }
    }
}

@Composable
private fun MessageBubble(
    model: HomeViewModel,
    home: String,
    message: Message,
    cancel: () -> Unit,
) {
    val fromTelegram = message.channel == "telegram"
    val own = message.inbound && !fromTelegram
    val color =
        if (own) MaterialTheme.colorScheme.secondaryContainer
        else MaterialTheme.colorScheme.surfaceContainer
    Column(
        Modifier.fillMaxWidth().testTag("message-" + message.id),
        horizontalAlignment = if (own) Alignment.End else Alignment.Start,
    ) {
        if (fromTelegram)
            Text(
                listOfNotNull(message.origin ?: "Telegram", message.author).joinToString(" · "),
                style = MaterialTheme.typography.labelSmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                modifier = Modifier.padding(start = 8.dp, bottom = 4.dp),
            )
        Surface(
            shape = RoundedCornerShape(20.dp),
            color = color,
            modifier = Modifier.widthIn(max = 600.dp).fillMaxWidth(if (own) 0.93f else 1f),
        ) {
            Column(Modifier.padding(14.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                if (message.text.isNotEmpty()) {
                    if (own)
                        SelectionContainer {
                            Text(message.text, style = MaterialTheme.typography.bodyLarge)
                        }
                    else MarkdownText(message.text)
                }
                message.files.forEach { AttachmentView(model, home, it) }
                message.error?.let {
                    Text(
                        it,
                        color = MaterialTheme.colorScheme.error,
                        style = MaterialTheme.typography.bodySmall,
                    )
                }
                if (message.working)
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        CircularProgressIndicator(Modifier.size(16.dp), strokeWidth = 2.dp)
                        Text(
                            if (message.status == "queued") "В очереди" else "Работает…",
                            Modifier.padding(horizontal = 10.dp).weight(1f),
                            style = MaterialTheme.typography.labelMedium,
                        )
                        TextButton(onClick = cancel) { Text("Остановить") }
                    }
            }
        }
        val time =
            remember(message.date) {
                runCatching {
                        Instant.parse(message.date)
                            .atZone(ZoneId.systemDefault())
                            .format(DateTimeFormatter.ofPattern("d MMM · HH:mm"))
                    }
                    .getOrDefault("")
            }
        Text(
            time,
            style = MaterialTheme.typography.labelSmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
            modifier = Modifier.padding(horizontal = 8.dp, vertical = 4.dp),
        )
    }
}

@Composable
private fun MarkdownText(text: String) {
    val context = LocalContext.current
    val markwon =
        remember(context) {
            Markwon.builder(context).usePlugin(TablePlugin.create(context)).build()
        }
    val foreground = MaterialTheme.colorScheme.onSurface.toArgb()
    val link = MaterialTheme.colorScheme.primary.toArgb()
    // No remote image loader: opening a message cannot issue arbitrary network requests.
    AndroidView(
        factory = {
            TextView(it).apply {
                textSize = 16f
                setTextIsSelectable(true)
                setLineSpacing(0f, 1.12f)
            }
        },
        update = { v ->
            v.setTextColor(foreground)
            v.setLinkTextColor(link)
            if (v.tag != text) {
                markwon.setMarkdown(v, text)
                v.tag = text
            }
        },
        modifier = Modifier.fillMaxWidth(),
    )
}

@Composable
private fun AttachmentView(model: HomeViewModel, home: String, attachment: Attachment) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    var local by remember(home, attachment.id) { mutableStateOf<File?>(null) }
    var busy by remember { mutableStateOf(false) }
    val image = attachment.mimeType.startsWith("image/")
    LaunchedEffect(home, attachment.id) {
        if (image && attachment.size <= 5L * 1024 * 1024)
            try {
                local = model.attachment(home, attachment)
            } catch (e: Exception) {
                if (e is CancellationException) throw e
            }
    }
    fun open() {
        if (busy) return
        busy = true
        scope.launch {
            try {
                val file = local ?: model.attachment(home, attachment).also { local = it }
                val displayName =
                    attachment.name
                        .replace('/', '_')
                        .replace('\\', '_')
                        .filterNot { it.isISOControl() }
                        .take(200)
                        .ifBlank { "Файл" }
                val uri =
                    FileProvider.getUriForFile(
                        context,
                        context.packageName + ".files",
                        file,
                        displayName,
                    )
                context.startActivity(
                    Intent.createChooser(
                        Intent(Intent.ACTION_VIEW)
                            .setDataAndType(uri, attachment.mimeType)
                            .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION),
                        "Открыть файл",
                    )
                )
            } catch (e: Exception) {
                if (e is CancellationException) throw e
                model.notice(friendlyError(e))
            } finally {
                busy = false
            }
        }
    }
    Surface(
        onClick = ::open,
        shape = RoundedCornerShape(12.dp),
        color = MaterialTheme.colorScheme.surfaceContainerHigh,
    ) {
        Column {
            if (image && local != null)
                AsyncImage(local, null, Modifier.fillMaxWidth().heightIn(max = 240.dp))
            Row(Modifier.padding(12.dp), verticalAlignment = Alignment.CenterVertically) {
                Icon(if (image) Icons.Rounded.Image else Icons.Rounded.Description, null)
                Text(
                    attachment.name,
                    Modifier.weight(1f).padding(horizontal = 10.dp),
                    maxLines = 2,
                    overflow = TextOverflow.Ellipsis,
                    style = MaterialTheme.typography.bodyMedium,
                )
                if (busy) CircularProgressIndicator(Modifier.size(20.dp))
                else Icon(Icons.Rounded.OpenInNew, "Открыть файл")
            }
        }
    }
}

@Composable
private fun Composer(
    model: HomeViewModel,
    state: AppState,
    ref: ChatRef,
    enabled: Boolean,
    modelName: String?,
    modelAvailable: Boolean,
    onModel: () -> Unit,
    onSent: () -> Unit,
) {
    val context = LocalContext.current
    val owner = LocalLifecycleOwner.current
    val draft = state.drafts[ref.key] ?: Draft()
    val transcribing = ref.key in state.transcribing
    val recorder = remember(ref) { VoiceCapture(context.applicationContext) }
    var recording by remember(ref) { mutableStateOf(false) }
    var levels by remember(ref) { mutableStateOf(List(36) { 0.04f }) }
    var seconds by remember(ref) { mutableIntStateOf(0) }
    var mode by rememberSaveable(ref.key) { mutableStateOf("steer") }
    var modeMenu by remember { mutableStateOf(false) }
    fun start() {
        try {
            recorder.start()
            recording = true
            seconds = 0
        } catch (_: Exception) {
            model.notice("Не удалось начать запись. Проверьте доступ к микрофону.")
        }
    }
    fun finish(discard: Boolean = false, transcribe: Boolean = true) {
        val file = recorder.stop(discard)
        recording = false
        if (file != null) {
            model.saveRecording(ref, file)
            if (transcribe) model.transcribe(ref)
        }
    }
    val permission =
        rememberLauncherForActivityResult(ActivityResultContracts.RequestPermission()) {
            if (it) start()
            else model.notice("Разрешите микрофон в настройках Android, чтобы диктовать.")
        }
    val picker =
        rememberLauncherForActivityResult(ActivityResultContracts.OpenMultipleDocuments()) {
            if (it.isNotEmpty()) model.addFiles(ref, it)
        }
    DisposableEffect(recorder, owner) {
        val observer = LifecycleEventObserver { _, event ->
            if (event == Lifecycle.Event.ON_STOP && recorder.recording) finish(transcribe = false)
        }
        owner.lifecycle.addObserver(observer)
        onDispose {
            owner.lifecycle.removeObserver(observer)
            if (recorder.recording) finish(transcribe = false)
        }
    }
    LaunchedEffect(recording) {
        while (recording) {
            levels = (levels + recorder.level().coerceIn(0.04f, 1f)).takeLast(36)
            seconds = ((System.currentTimeMillis() - recorder.startedAt) / 1000).toInt()
            delay(120)
        }
    }
    Surface(
        color = MaterialTheme.colorScheme.surfaceContainer,
        shape = RoundedCornerShape(topStart = 24.dp, topEnd = 24.dp),
        modifier = Modifier.fillMaxWidth(),
    ) {
        Column(Modifier.padding(horizontal = 12.dp, vertical = 8.dp)) {
            if (recording)
                Row(
                    verticalAlignment = Alignment.CenterVertically,
                    modifier = Modifier.heightIn(min = 64.dp),
                ) {
                    IconButton(onClick = { finish(discard = true) }) {
                        Icon(Icons.Rounded.Close, "Отменить запись")
                    }
                    val wave = MaterialTheme.colorScheme.primary
                    Canvas(Modifier.weight(1f).height(36.dp)) {
                        levels.forEachIndexed { i, l ->
                            val x = size.width * i / levels.size
                            drawLine(
                                wave,
                                Offset(x, size.height * (1 - l) / 2),
                                Offset(x, size.height * (1 + l) / 2),
                                4.dp.toPx(),
                                StrokeCap.Round,
                            )
                        }
                    }
                    Text(
                        "${seconds/60}:${(seconds%60).toString().padStart(2,'0')}",
                        style = MaterialTheme.typography.labelMedium,
                        modifier = Modifier.padding(8.dp),
                    )
                    FilledIconButton(
                        onClick = { finish() },
                        modifier = Modifier.testTag("stop-dictation"),
                    ) {
                        Icon(Icons.Rounded.Stop, "Завершить диктовку")
                    }
                }
            else {
                if (draft.recording != null)
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        if (transcribing)
                            CircularProgressIndicator(
                                Modifier.padding(8.dp).size(18.dp),
                                strokeWidth = 2.dp,
                            )
                        Text(
                            if (transcribing) "Распознаём…" else "Запись сохранена",
                            Modifier.weight(1f).padding(start = 8.dp),
                            style = MaterialTheme.typography.bodySmall,
                        )
                        if (!transcribing) {
                            TextButton(onClick = { model.transcribe(ref) }) { Text("Распознать") }
                            IconButton(
                                onClick = { model.saveDraft(ref, draft.copy(recording = null)) }
                            ) {
                                Icon(Icons.Rounded.Close, "Убрать запись")
                            }
                        }
                    }
                draft.files.forEach { f ->
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Icon(Icons.Rounded.AttachFile, null, Modifier.size(18.dp))
                        Text(
                            f.name,
                            Modifier.weight(1f).padding(8.dp),
                            maxLines = 1,
                            overflow = TextOverflow.Ellipsis,
                            style = MaterialTheme.typography.bodySmall,
                        )
                        IconButton(
                            onClick = {
                                model.saveDraft(
                                    ref,
                                    draft.copy(files = draft.files.filterNot { it.id == f.id }),
                                )
                            }
                        ) {
                            Icon(Icons.Rounded.Close, "Убрать ${f.name}")
                        }
                    }
                }
                OutlinedTextField(
                    value = draft.text,
                    onValueChange = { model.saveDraft(ref, draft.copy(text = it)) },
                    placeholder = { Text("Сообщение") },
                    modifier = Modifier.fillMaxWidth().testTag("composer"),
                    minLines = 1,
                    maxLines = 6,
                    shape = RoundedCornerShape(16.dp),
                    enabled = enabled,
                    colors =
                        OutlinedTextFieldDefaults.colors(
                            unfocusedBorderColor = MaterialTheme.colorScheme.surfaceContainer,
                            focusedBorderColor = MaterialTheme.colorScheme.primary,
                        ),
                )
                Row(verticalAlignment = Alignment.CenterVertically) {
                    IconButton(enabled = enabled, onClick = { picker.launch(arrayOf("*/*")) }) {
                        Icon(Icons.Rounded.Add, "Добавить файл")
                    }
                    if (modelAvailable)
                        TextButton(
                            onClick = onModel,
                            modifier = Modifier.weight(1f),
                            contentPadding = PaddingValues(horizontal = 4.dp),
                        ) {
                            Text(
                                modelName ?: "Модель сотрудника",
                                maxLines = 1,
                                overflow = TextOverflow.Ellipsis,
                                style = MaterialTheme.typography.labelMedium,
                            )
                            Icon(Icons.Rounded.ExpandMore, null, Modifier.size(16.dp))
                        }
                    else Spacer(Modifier.weight(1f))
                    if (state.homes[ref.home]?.health?.optInt("turnControlVersion") == 1)
                        Box {
                            IconButton(onClick = { modeMenu = true }) {
                                Icon(
                                    when (mode) {
                                        "queue" -> Icons.Rounded.PlaylistAdd
                                        "interrupt" -> Icons.Rounded.RestartAlt
                                        else -> Icons.Rounded.SubdirectoryArrowRight
                                    },
                                    "Отправка: " +
                                        when (mode) {
                                            "queue" -> "После ответа"
                                            "interrupt" -> "Начать заново"
                                            else -> "Уточнить задачу"
                                        },
                                )
                            }
                            DropdownMenu(modeMenu, { modeMenu = false }) {
                                listOf(
                                        "steer" to "Уточнить задачу",
                                        "queue" to "После ответа",
                                        "interrupt" to "Начать заново",
                                    )
                                    .forEach { (value, label) ->
                                        DropdownMenuItem(
                                            text = { Text(label) },
                                            leadingIcon = {
                                                if (mode == value) Icon(Icons.Rounded.Check, null)
                                            },
                                            onClick = {
                                                mode = value
                                                modeMenu = false
                                            },
                                        )
                                    }
                            }
                        }
                    IconButton(
                        enabled = enabled && !transcribing && draft.recording == null,
                        onClick = {
                            if (
                                ContextCompat.checkSelfPermission(
                                    context,
                                    Manifest.permission.RECORD_AUDIO,
                                ) == PackageManager.PERMISSION_GRANTED
                            )
                                start()
                            else permission.launch(Manifest.permission.RECORD_AUDIO)
                        },
                        modifier = Modifier.testTag("dictate"),
                    ) {
                        Icon(Icons.Rounded.Mic, "Диктовать")
                    }
                    FilledIconButton(
                        enabled =
                            enabled &&
                                ref.key !in state.sending &&
                                (draft.text.isNotBlank() || draft.files.isNotEmpty()),
                        onClick = {
                            model.send(ref, mode)
                            onSent()
                        },
                        modifier = Modifier.testTag("send-message"),
                    ) {
                        Icon(Icons.AutoMirrored.Rounded.Send, "Отправить")
                    }
                }
            }
        }
    }
}
