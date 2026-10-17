@file:OptIn(androidx.compose.material3.ExperimentalMaterial3Api::class)

package app.openstrudel

import android.net.Uri
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.rounded.ArrowBack
import androidx.compose.material.icons.automirrored.rounded.KeyboardArrowRight
import androidx.compose.material.icons.rounded.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalClipboard
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.compose.LocalLifecycleOwner
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.repeatOnLifecycle
import androidx.navigation3.runtime.NavKey
import androidx.navigation3.runtime.entryProvider
import androidx.navigation3.runtime.rememberNavBackStack
import androidx.navigation3.ui.NavDisplay
import coil3.compose.AsyncImage
import com.google.mlkit.vision.barcode.common.Barcode
import com.google.mlkit.vision.codescanner.GmsBarcodeScannerOptions
import com.google.mlkit.vision.codescanner.GmsBarcodeScanning
import io.noties.markwon.Markwon
import java.util.UUID
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.launch
import kotlinx.serialization.Serializable

@Serializable data object EmployeesRoute : NavKey

@Serializable data object ConnectionsRoute : NavKey

@Serializable data object ConnectRoute : NavKey

@Serializable data object HiddenRoute : NavKey

@Serializable data class ChatRoute(val home: String, val employee: String) : NavKey

@Serializable data class EmployeeRoute(val home: String, val employee: String? = null) : NavKey

@Serializable data class ModelsRoute(val home: String, val employee: String) : NavKey

@Serializable data class ServicesRoute(val home: String, val employee: String) : NavKey

@Serializable data class SchedulesRoute(val home: String, val employee: String) : NavKey

@Composable
fun OpenStrudelApp(model: HomeViewModel) {
    val state by model.state.collectAsStateWithLifecycle()
    val stack = rememberNavBackStack(EmployeesRoute)
    val snackbar = remember { SnackbarHostState() }
    val owner = LocalLifecycleOwner.current
    LaunchedEffect(owner) {
        owner.lifecycle.repeatOnLifecycle(Lifecycle.State.STARTED) { model.foregroundLoop() }
    }
    LaunchedEffect(state.notice) {
        state.notice?.let {
            snackbar.showSnackbar(it)
            model.notice(null)
        }
    }
    LaunchedEffect(stack.lastOrNull()) {
        val current = stack.lastOrNull()
        model.setVisible((current as? ChatRoute)?.let { ChatRef(it.home, it.employee) })
    }
    LaunchedEffect(state.pairing, state.invitation) {
        if (state.pairing && state.invitation == null && stack.lastOrNull() == ConnectRoute) {
            while (stack.size > 1) stack.removeLastOrNull()
        }
    }
    val back: () -> Unit = { if (stack.size > 1) stack.removeLastOrNull() }
    val open: (NavKey) -> Unit = { key -> if (stack.lastOrNull() != key) stack.add(key) }
    Surface(Modifier.fillMaxSize(), color = MaterialTheme.colorScheme.background) {
        Box {
            when {
                !state.loaded ->
                    Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                        CircularProgressIndicator()
                    }
                state.fatal != null ->
                    Column(
                        Modifier.fillMaxSize().safeDrawingPadding().padding(24.dp),
                        verticalArrangement = Arrangement.Center,
                    ) {
                        Text(state.fatal!!)
                        Button(onClick = model::load, modifier = Modifier.padding(top = 16.dp)) {
                            Text("Повторить")
                        }
                    }
                else ->
                    NavDisplay(
                        backStack = stack,
                        onBack = back,
                        entryProvider =
                            entryProvider {
                                entry<EmployeesRoute> { EmployeesScreen(model, state, open) }
                                entry<ConnectionsRoute> {
                                    ConnectionsScreen(model, state, back) { open(ConnectRoute) }
                                }
                                entry<ConnectRoute> { ConnectScreen(model, back) }
                                entry<HiddenRoute> { HiddenScreen(model, state, back) }
                                entry<ChatRoute> { key ->
                                    ChatScreen(
                                        model,
                                        state,
                                        ChatRef(key.home, key.employee),
                                        back,
                                        open,
                                    )
                                }
                                entry<EmployeeRoute> { key ->
                                    EmployeeScreen(model, state, key, back) { id ->
                                        back()
                                        open(ChatRoute(key.home, id))
                                    }
                                }
                                entry<ModelsRoute> { key ->
                                    ModelScreen(model, ChatRef(key.home, key.employee), back)
                                }
                                entry<ServicesRoute> { key ->
                                    ServicesScreen(model, ChatRef(key.home, key.employee), back)
                                }
                                entry<SchedulesRoute> { key ->
                                    SchedulesScreen(model, ChatRef(key.home, key.employee), back)
                                }
                            },
                    )
            }
            SnackbarHost(
                snackbar,
                Modifier.align(Alignment.BottomCenter).safeDrawingPadding().imePadding(),
            )
        }
        state.invitation?.let { invitation ->
            AlertDialog(
                onDismissRequest = model::dismissInvitation,
                icon = { Icon(Icons.Rounded.Devices, null) },
                title = { Text("Подключить «${invitation.name}»?") },
                text = {
                    Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                        Text(
                            "Сотрудники продолжат работать на этом устройстве. Вы сможете общаться с ними с телефона."
                        )
                        Text(
                            invitation.host,
                            style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                        state.notice?.let { Text(it, color = MaterialTheme.colorScheme.error) }
                    }
                },
                confirmButton = {
                    TextButton(
                        onClick = model::pair,
                        enabled = !state.pairing,
                        modifier = Modifier.testTag("confirm-pair"),
                    ) {
                        if (state.pairing) CircularProgressIndicator(Modifier.size(20.dp))
                        else Text("Подключить")
                    }
                },
                dismissButton = {
                    TextButton(onClick = model::dismissInvitation, enabled = !state.pairing) {
                        Text("Отмена")
                    }
                },
            )
        }
    }
}

@Composable
fun BackButton(back: () -> Unit) {
    IconButton(onClick = back) { Icon(Icons.AutoMirrored.Rounded.ArrowBack, "Назад") }
}

@Composable
fun Avatar(character: String, main: Boolean = false, size: Int = 48) {
    val image =
        if (main) R.drawable.agent_main
        else
            when (character) {
                "fold" -> R.drawable.agent_fold
                "knot" -> R.drawable.agent_knot
                "curl" -> R.drawable.agent_curl
                "wave" -> R.drawable.agent_wave
                "pillow" -> R.drawable.agent_pillow
                else -> R.drawable.agent_coil
            }
    AsyncImage(model = image, contentDescription = null, modifier = Modifier.size(size.dp))
}

fun employee(state: AppState, ref: ChatRef): Employee? =
    if (ref.employee == "main")
        Employee("main", "OpenStrudel", "", "Помощник для ваших задач", "main", null)
    else state.homes[ref.home]?.employees?.firstOrNull { it.id == ref.employee }

@Composable
private fun EmployeesScreen(model: HomeViewModel, state: AppState, open: (NavKey) -> Unit) {
    var menu by remember { mutableStateOf(false) }
    var createChoice by remember { mutableStateOf(false) }
    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text("Сотрудники") },
                actions = {
                    IconButton(onClick = { open(ConnectionsRoute) }) {
                        Icon(Icons.Rounded.Devices, "Устройства")
                    }
                    Box {
                        IconButton(onClick = { menu = true }) {
                            Icon(Icons.Rounded.Add, "Добавить")
                        }
                        DropdownMenu(expanded = menu, onDismissRequest = { menu = false }) {
                            if (state.stored.connections.isNotEmpty())
                                DropdownMenuItem(
                                    text = { Text("Создать сотрудника") },
                                    onClick = {
                                        menu = false
                                        if (state.stored.connections.size == 1)
                                            open(EmployeeRoute(state.stored.connections.first().id))
                                        else createChoice = true
                                    },
                                )
                            DropdownMenuItem(
                                text = { Text("Подключить устройство") },
                                onClick = {
                                    menu = false
                                    open(ConnectRoute)
                                },
                            )
                            if (state.stored.hidden.isNotEmpty())
                                DropdownMenuItem(
                                    text = { Text("Скрытые сотрудники") },
                                    onClick = {
                                        menu = false
                                        open(HiddenRoute)
                                    },
                                )
                        }
                    }
                },
            )
        }
    ) { insets ->
        if (state.stored.connections.isEmpty()) {
            Column(
                Modifier.fillMaxSize()
                    .padding(insets)
                    .consumeWindowInsets(insets)
                    .verticalScroll(rememberScrollState())
                    .padding(horizontal = 28.dp, vertical = 48.dp),
                horizontalAlignment = Alignment.CenterHorizontally,
                verticalArrangement = Arrangement.Center,
            ) {
                Avatar("main", true, 96)
                Text(
                    "Ваши сотрудники\nвсегда рядом",
                    style = MaterialTheme.typography.headlineLarge,
                    modifier = Modifier.padding(top = 24.dp, bottom = 16.dp),
                )
                Text(
                    "Подключите OpenStrudel на Mac или сервере и продолжайте с телефона.",
                    style = MaterialTheme.typography.bodyLarge,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
                Button(
                    onClick = { open(ConnectRoute) },
                    modifier = Modifier.fillMaxWidth().padding(top = 32.dp).heightIn(min = 52.dp),
                ) {
                    Text("Подключить устройство")
                }
            }
        } else
            LazyColumn(
                Modifier.fillMaxSize().consumeWindowInsets(insets),
                contentPadding = insets,
            ) {
                state.stored.connections.forEach { c ->
                    val home = state.homes[c.id]
                    item("home:" + c.id) {
                        Row(
                            Modifier.fillMaxWidth()
                                .padding(start = 20.dp, end = 16.dp, top = 20.dp, bottom = 8.dp),
                            verticalAlignment = Alignment.CenterVertically,
                        ) {
                            Text(
                                c.name,
                                style = MaterialTheme.typography.labelLarge,
                                color = MaterialTheme.colorScheme.onSurfaceVariant,
                                modifier = Modifier.weight(1f),
                            )
                            if (home?.online != true)
                                Text(
                                    if (home == null) "Подключаемся…" else "Нет связи",
                                    style = MaterialTheme.typography.labelSmall,
                                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                                )
                        }
                    }
                    val list =
                        listOf(
                            Employee(
                                "main",
                                "OpenStrudel",
                                "",
                                "Помощник для ваших задач",
                                "main",
                                null,
                            )
                        ) + (home?.employees ?: emptyList()).filterNot { it.id == "main" }
                    items(
                        list.filterNot { chatKey(c.id, it.id) in state.stored.hidden },
                        key = { c.id + ":" + it.id },
                    ) { p ->
                        EmployeeRow(p, c.id, model, home?.canManage == true, open)
                    }
                    if (home?.error != null)
                        item("error:" + c.id) {
                            TextButton(
                                onClick = model::refreshNow,
                                modifier = Modifier.padding(horizontal = 12.dp),
                            ) {
                                Text(home.error, maxLines = 3)
                            }
                        }
                }
                item { Spacer(Modifier.height(24.dp)) }
            }
    }
    if (createChoice)
        AlertDialog(
            onDismissRequest = { createChoice = false },
            title = { Text("Где будет работать сотрудник?") },
            text = {
                Column {
                    state.stored.connections.forEach { c ->
                        TextButton(
                            onClick = {
                                createChoice = false
                                open(EmployeeRoute(c.id))
                            },
                            modifier = Modifier.fillMaxWidth(),
                        ) {
                            Text(c.name)
                        }
                    }
                }
            },
            confirmButton = {},
            dismissButton = { TextButton(onClick = { createChoice = false }) { Text("Отмена") } },
        )
}

@Composable
private fun EmployeeRow(
    p: Employee,
    home: String,
    model: HomeViewModel,
    canManage: Boolean,
    open: (NavKey) -> Unit,
) {
    var menu by remember { mutableStateOf(false) }
    var deleting by remember { mutableStateOf(false) }
    val ref = ChatRef(home, p.id)
    val context = LocalContext.current
    val markdown = remember(context) { Markwon.create(context) }
    val preview = remember(markdown, p.preview) { markdown.toMarkdown(p.preview).toString() }
    Box {
        ListItem(
            headlineContent = { Text(p.name, maxLines = 1, overflow = TextOverflow.Ellipsis) },
            supportingContent = {
                Text(
                    preview
                        .ifBlank {
                            if (p.id == "main") "Помощник для ваших задач"
                            else "Напишите, что нужно"
                        }
                        .replace('\n', ' '),
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                )
            },
            leadingContent = { Avatar(p.character, p.id == "main") },
            trailingContent = {
                Icon(
                    Icons.AutoMirrored.Rounded.KeyboardArrowRight,
                    null,
                    tint = MaterialTheme.colorScheme.outline,
                )
            },
            colors = ListItemDefaults.colors(containerColor = MaterialTheme.colorScheme.background),
            modifier =
                Modifier.fillMaxWidth()
                    .testTag("employee-${p.id}")
                    .combinedClickable(
                        onClick = { open(ChatRoute(home, p.id)) },
                        onLongClick = { menu = true },
                    ),
        )
        DropdownMenu(expanded = menu, onDismissRequest = { menu = false }) {
            DropdownMenuItem(
                text = { Text("Открыть") },
                onClick = {
                    menu = false
                    open(ChatRoute(home, p.id))
                },
            )
            if (p.id != "main")
                DropdownMenuItem(
                    text = { Text("Настроить") },
                    onClick = {
                        menu = false
                        open(EmployeeRoute(home, p.id))
                    },
                )
            DropdownMenuItem(
                text = { Text("Скрыть на этом телефоне") },
                onClick = {
                    menu = false
                    model.hide(ref, true)
                },
            )
            if (p.id != "main" && canManage)
                DropdownMenuItem(
                    text = { Text("Удалить…") },
                    onClick = {
                        menu = false
                        deleting = true
                    },
                )
        }
    }
    if (deleting)
        DeleteEmployeeDialog(p.name, { deleting = false }) {
            deleting = false
            model.delete(ref) {}
        }
}

@Composable
private fun ConnectionsScreen(
    model: HomeViewModel,
    state: AppState,
    back: () -> Unit,
    add: () -> Unit,
) {
    var removal by remember { mutableStateOf<Connection?>(null) }
    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text("Устройства") },
                navigationIcon = { BackButton(back) },
                actions = {
                    IconButton(onClick = add) { Icon(Icons.Rounded.Add, "Подключить устройство") }
                },
            )
        }
    ) { insets ->
        LazyColumn(Modifier.fillMaxSize().consumeWindowInsets(insets), contentPadding = insets) {
            item {
                Text(
                    "Сотрудники работают на подключённых компьютерах и серверах.",
                    Modifier.padding(20.dp),
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
            items(state.stored.connections, key = { it.id }) { c ->
                ListItem(
                    headlineContent = { Text(c.name) },
                    supportingContent = {
                        Text(if (state.homes[c.id]?.online == true) "На связи" else "Нет связи")
                    },
                    leadingContent = { Icon(Icons.Rounded.Computer, null) },
                    trailingContent = {
                        IconButton(onClick = { removal = c }) {
                            Icon(Icons.Rounded.LinkOff, "Отключить ${c.name}")
                        }
                    },
                )
            }
            item {
                TextButton(onClick = add, modifier = Modifier.padding(12.dp)) {
                    Icon(Icons.Rounded.Add, null)
                    Spacer(Modifier.width(8.dp))
                    Text("Подключить устройство")
                }
            }
        }
    }
    removal?.let { c ->
        AlertDialog(
            onDismissRequest = { removal = null },
            title = { Text("Отключить «${c.name}»?") },
            text = {
                Text(
                    "Подключение исчезнет с этого телефона. Сотрудники и переписки останутся на устройстве."
                )
            },
            confirmButton = {
                TextButton(
                    onClick = {
                        removal = null
                        model.removeHome(c.id)
                    }
                ) {
                    Text("Отключить")
                }
            },
            dismissButton = { TextButton(onClick = { removal = null }) { Text("Отмена") } },
        )
    }
}

@Composable
private fun ConnectScreen(model: HomeViewModel, back: () -> Unit) {
    var link by remember { mutableStateOf("") }
    var scanning by remember { mutableStateOf(false) }
    val context = LocalContext.current
    val clipboard = LocalClipboard.current
    val scope = rememberCoroutineScope()
    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text("Подключить устройство") },
                navigationIcon = { BackButton(back) },
            )
        },
        contentWindowInsets = WindowInsets.safeDrawing,
    ) { insets ->
        Column(
            Modifier.fillMaxSize()
                .padding(insets)
                .consumeWindowInsets(insets)
                .verticalScroll(rememberScrollState())
                .padding(24.dp),
            verticalArrangement = Arrangement.spacedBy(20.dp),
        ) {
            Icon(
                Icons.Rounded.Devices,
                null,
                Modifier.size(56.dp),
                tint = MaterialTheme.colorScheme.primary,
            )
            Text(
                "Откройте OpenStrudel на Mac или сервере: Устройства → Поделиться доступом.",
                style = MaterialTheme.typography.bodyLarge,
            )
            FilledTonalButton(
                enabled = !scanning,
                onClick = {
                    scanning = true
                    val options =
                        GmsBarcodeScannerOptions.Builder()
                            .setBarcodeFormats(Barcode.FORMAT_QR_CODE)
                            .enableAutoZoom()
                            .build()
                    GmsBarcodeScanning.getClient(context, options)
                        .startScan()
                        .addOnSuccessListener { it.rawValue?.let(model::inspectLink) }
                        .addOnFailureListener {
                            model.notice(
                                "Не удалось открыть сканер. Попробуйте ещё раз или вставьте ссылку."
                            )
                        }
                        .addOnCompleteListener { scanning = false }
                },
                modifier = Modifier.fillMaxWidth().heightIn(min = 52.dp).testTag("scan-qr"),
            ) {
                Icon(Icons.Rounded.QrCodeScanner, null)
                Spacer(Modifier.width(10.dp))
                Text(if (scanning) "Открываем сканер…" else "Сканировать QR-код")
            }
            HorizontalDivider()
            OutlinedTextField(
                value = link,
                onValueChange = { link = it },
                label = { Text("Ссылка приглашения") },
                singleLine = true,
                visualTransformation = PasswordVisualTransformation(),
                keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Uri),
                modifier = Modifier.fillMaxWidth().testTag("invitation-link"),
            )
            Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                OutlinedButton(
                    modifier = Modifier.fillMaxWidth(),
                    onClick = {
                        scope.launch {
                            clipboard
                                .getClipEntry()
                                ?.clipData
                                ?.getItemAt(0)
                                ?.coerceToText(context)
                                ?.toString()
                                ?.let { link = it }
                        }
                    },
                ) {
                    Text("Вставить")
                }
                Button(
                    onClick = { model.inspectLink(link) },
                    enabled = link.isNotBlank(),
                    modifier = Modifier.fillMaxWidth().testTag("review-link"),
                ) {
                    Text("Продолжить")
                }
            }
            Text(
                "Полученную ссылку также можно открыть прямо из сообщения.",
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
    }
}

@Composable
private fun HiddenScreen(model: HomeViewModel, state: AppState, back: () -> Unit) {
    Scaffold(
        topBar = {
            TopAppBar(title = { Text("Скрытые сотрудники") }, navigationIcon = { BackButton(back) })
        }
    ) { insets ->
        LazyColumn(Modifier.fillMaxSize().consumeWindowInsets(insets), contentPadding = insets) {
            state.stored.connections.forEach { c ->
                val all =
                    listOf(Employee("main", "OpenStrudel", "", "", "main", null)) +
                        (state.homes[c.id]?.employees ?: emptyList())
                items(
                    all.filter { chatKey(c.id, it.id) in state.stored.hidden },
                    key = { c.id + it.id },
                ) { p ->
                    ListItem(
                        headlineContent = { Text(p.name) },
                        supportingContent = { Text(c.name) },
                        leadingContent = { Avatar(p.character, p.id == "main") },
                        trailingContent = {
                            TextButton(onClick = { model.hide(ChatRef(c.id, p.id), false) }) {
                                Text("Показать")
                            }
                        },
                    )
                }
            }
        }
    }
}

@Composable
private fun EmployeeScreen(
    model: HomeViewModel,
    state: AppState,
    route: EmployeeRoute,
    back: () -> Unit,
    created: (String) -> Unit,
) {
    val initial = state.homes[route.home]?.employees?.firstOrNull { it.id == route.employee }
    var name by rememberSaveable(route) { mutableStateOf(initial?.name ?: "") }
    var instructions by rememberSaveable(route) { mutableStateOf(initial?.instructions ?: "") }
    var deleting by remember { mutableStateOf(false) }
    var saving by remember { mutableStateOf(false) }
    val requestId = rememberSaveable(route, name, instructions) { UUID.randomUUID().toString() }
    val scope = rememberCoroutineScope()
    val ref = route.employee?.let { ChatRef(route.home, it) }
    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text(if (ref == null) "Новый сотрудник" else "Сотрудник") },
                navigationIcon = { BackButton(back) },
                actions = {
                    TextButton(
                        enabled = !saving && name.isNotBlank(),
                        onClick = {
                            saving = true
                            scope.launch {
                                try {
                                    if (ref == null)
                                        created(
                                            model.create(route.home, name, instructions, requestId)
                                        )
                                    else {
                                        model.edit(ref, name, instructions)
                                        back()
                                    }
                                } catch (e: Exception) {
                                    if (e is CancellationException) throw e
                                    model.notice(friendlyError(e))
                                } finally {
                                    saving = false
                                }
                            }
                        },
                    ) {
                        Text(if (saving) "Сохраняем…" else "Сохранить")
                    }
                },
            )
        },
        contentWindowInsets = WindowInsets.safeDrawing,
    ) { insets ->
        Column(
            Modifier.fillMaxSize()
                .padding(insets)
                .consumeWindowInsets(insets)
                .verticalScroll(rememberScrollState())
                .padding(20.dp),
            verticalArrangement = Arrangement.spacedBy(20.dp),
        ) {
            Text(
                state.stored.connections.firstOrNull { it.id == route.home }?.name ?: "Устройство",
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
            OutlinedTextField(
                name,
                { name = it },
                label = { Text("Имя") },
                singleLine = true,
                modifier = Modifier.fillMaxWidth().testTag("employee-name"),
            )
            OutlinedTextField(
                instructions,
                { instructions = it },
                label = { Text("Чем занимается") },
                placeholder = { Text("Задачи, знания и характер сотрудника") },
                minLines = 5,
                maxLines = 12,
                modifier = Modifier.fillMaxWidth().testTag("employee-instructions"),
            )
            if (ref != null) {
                TextButton(
                    onClick = {
                        model.hide(ref, true)
                        back()
                    }
                ) {
                    Text("Скрыть на этом телефоне")
                }
                if (state.homes[route.home]?.canManage == true)
                    TextButton(
                        onClick = { deleting = true },
                        colors =
                            ButtonDefaults.textButtonColors(
                                contentColor = MaterialTheme.colorScheme.error
                            ),
                    ) {
                        Text("Удалить сотрудника…")
                    }
            }
            state.notice?.let { Text(it, color = MaterialTheme.colorScheme.error) }
        }
    }
    if (deleting && ref != null)
        DeleteEmployeeDialog(name, { deleting = false }) {
            deleting = false
            model.delete(ref, back)
        }
}

@Composable
private fun DeleteEmployeeDialog(name: String, dismiss: () -> Unit, confirm: () -> Unit) {
    AlertDialog(
        onDismissRequest = dismiss,
        title = { Text("Удалить «$name»?") },
        text = {
            Text(
                "Сотрудник, его переписки и расписания будут удалены на устройстве для всех, кто к нему подключён."
            )
        },
        confirmButton = {
            TextButton(onClick = confirm) {
                Text("Удалить", color = MaterialTheme.colorScheme.error)
            }
        },
        dismissButton = { TextButton(onClick = dismiss) { Text("Отмена") } },
    )
}
