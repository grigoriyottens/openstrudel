@file:OptIn(androidx.compose.material3.ExperimentalMaterial3Api::class)

package app.openstrudel

import android.content.Intent
import android.net.Uri
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.unit.dp
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.compose.LocalLifecycleOwner
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.repeatOnLifecycle
import java.time.Instant
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.launch
import org.json.JSONObject

@Composable
fun ModelScreen(model: HomeViewModel, ref: ChatRef, back: () -> Unit) {
    var data by remember { mutableStateOf<JSONObject?>(null) }
    var error by remember { mutableStateOf<String?>(null) }
    var saving by remember { mutableStateOf(false) }
    var choice by remember { mutableStateOf<JSONObject?>(null) }
    var speed by remember { mutableStateOf<String?>(null) }
    var effort by remember { mutableStateOf<String?>(null) }
    val scope = rememberCoroutineScope()
    suspend fun load() {
        try {
            error = null
            data = model.models(ref)
        } catch (e: Exception) {
            if (e is CancellationException) throw e
            error = friendlyError(e)
        }
    }
    LaunchedEffect(ref) { load() }
    fun save(value: JSONObject) {
        error = null
        saving = true
        scope.launch {
            try {
                model.saveModel(ref, value)
                back()
            } catch (e: Exception) {
                if (e is CancellationException) throw e
                error = friendlyError(e)
            } finally {
                saving = false
            }
        }
    }
    Scaffold(
        topBar = {
            TopAppBar(title = { Text("Модель чата") }, navigationIcon = { BackButton(back) })
        }
    ) { insets ->
        LazyColumn(Modifier.fillMaxSize().consumeWindowInsets(insets), contentPadding = insets) {
            item {
                Text(
                    "Выбор действует только в этой переписке.",
                    Modifier.padding(20.dp),
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
            if (data == null && error == null)
                item { LinearProgressIndicator(Modifier.fillMaxWidth()) }
            error?.let {
                item {
                    TextButton(
                        onClick = { scope.launch { load() } },
                        modifier = Modifier.padding(12.dp),
                    ) {
                        Text(it)
                    }
                }
            }
            data?.let { settings ->
                val canManage = settings.optBoolean("canManage")
                val selected = settings.optJSONObject("selection") ?: JSONObject()
                item {
                    ListItem(
                        headlineContent = { Text("Как у сотрудника") },
                        supportingContent = { Text("Использовать его настройки по умолчанию") },
                        trailingContent = {
                            if (selected.string("model") == null) Icon(Icons.Rounded.Check, null)
                        },
                        modifier =
                            Modifier.clickable(enabled = canManage && !saving) {
                                save(
                                    json(
                                        "provider" to null,
                                        "model" to null,
                                        "serviceTier" to null,
                                        "reasoningEffort" to null,
                                    )
                                )
                            },
                    )
                }
                val providers =
                    settings.objects("providers").associate {
                        it.optString("id") to it.optString("name")
                    }
                settings
                    .objects("models")
                    .groupBy { it.string("provider") ?: "" }
                    .forEach { (provider, models) ->
                        if (providers.size > 1)
                            item {
                                Text(
                                    providers[provider] ?: provider,
                                    Modifier.padding(20.dp),
                                    style = MaterialTheme.typography.labelLarge,
                                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                                )
                            }
                        items(
                            models,
                            key = { (it.string("provider") ?: "") + ":" + it.getString("id") },
                        ) { m ->
                            val active =
                                m.string("id") == selected.string("model") &&
                                    m.string("provider") == selected.string("provider")
                            ListItem(
                                headlineContent = { Text(m.optString("name", m.getString("id"))) },
                                supportingContent = { m.string("description")?.let { Text(it) } },
                                trailingContent = { if (active) Icon(Icons.Rounded.Check, null) },
                                modifier =
                                    Modifier.clickable(enabled = canManage && !saving) {
                                        choice = m
                                        speed = if (active) selected.string("serviceTier") else null
                                        effort =
                                            if (active) selected.string("reasoningEffort") else null
                                    },
                            )
                        }
                    }
                if (!canManage)
                    item {
                        Text(
                            "Модель выбирает владелец устройства.",
                            Modifier.padding(20.dp),
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                    }
            }
        }
    }
    choice?.let { m ->
        AlertDialog(
            onDismissRequest = { if (!saving) choice = null },
            title = { Text(m.optString("name", m.getString("id"))) },
            text = {
                Column(
                    Modifier.verticalScroll(rememberScrollState()),
                    verticalArrangement = Arrangement.spacedBy(16.dp),
                ) {
                    OptionMenu("Скорость", m.objects("speeds"), speed) { speed = it }
                    OptionMenu("Глубина рассуждений", m.objects("reasoningEfforts"), effort) {
                        effort = it
                    }
                    if (m.objects("speeds").isEmpty() && m.objects("reasoningEfforts").isEmpty())
                        Text("Использовать эту модель в текущей переписке.")
                    error?.let { Text(it, color = MaterialTheme.colorScheme.error) }
                }
            },
            confirmButton = {
                TextButton(
                    enabled = !saving,
                    onClick = {
                        save(
                            json(
                                "provider" to m.string("provider"),
                                "model" to m.getString("id"),
                                "serviceTier" to speed,
                                "reasoningEffort" to effort,
                            )
                        )
                    },
                ) {
                    Text(if (saving) "Сохраняем…" else "Выбрать")
                }
            },
            dismissButton = {
                TextButton(enabled = !saving, onClick = { choice = null }) { Text("Отмена") }
            },
        )
    }
}

@Composable
private fun OptionMenu(
    label: String,
    options: List<JSONObject>,
    value: String?,
    choose: (String?) -> Unit,
) {
    if (options.isEmpty()) return
    var expanded by remember { mutableStateOf(false) }
    Column {
        Text(label, style = MaterialTheme.typography.labelLarge)
        Box {
            OutlinedButton(onClick = { expanded = true }, modifier = Modifier.fillMaxWidth()) {
                Text(
                    options.firstOrNull { it.string("id") == value }?.string("name")
                        ?: "По умолчанию",
                    Modifier.weight(1f),
                )
                Icon(Icons.Rounded.ExpandMore, null)
            }
            DropdownMenu(expanded, { expanded = false }) {
                DropdownMenuItem(
                    text = { Text("По умолчанию") },
                    onClick = {
                        choose(null)
                        expanded = false
                    },
                )
                options.forEach { o ->
                    DropdownMenuItem(
                        text = { Text(o.optString("name", o.getString("id"))) },
                        onClick = {
                            choose(o.getString("id"))
                            expanded = false
                        },
                    )
                }
            }
        }
        options
            .firstOrNull { it.string("id") == value }
            ?.string("description")
            ?.let {
                Text(
                    it,
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
    }
}

@Composable
fun ServicesScreen(model: HomeViewModel, ref: ChatRef, back: () -> Unit) {
    val state by model.state.collectAsStateWithLifecycle()
    val canManage = state.homes[ref.home]?.canManage == true
    var data by remember { mutableStateOf<JSONObject?>(null) }
    var extensions by remember { mutableStateOf<JSONObject?>(null) }
    var error by remember { mutableStateOf<String?>(null) }
    var busy by remember { mutableStateOf<String?>(null) }
    var add by remember { mutableStateOf(false) }
    var mcp by remember { mutableStateOf(false) }
    var preview by remember { mutableStateOf<JSONObject?>(null) }
    var skillFile by remember { mutableStateOf<LocalFile?>(null) }
    val context = LocalContext.current
    val owner = LocalLifecycleOwner.current
    val scope = rememberCoroutineScope()
    suspend fun load() {
        try {
            error = null
            data = model.services(ref)
            extensions = model.extensions(ref)
        } catch (e: Exception) {
            if (e is CancellationException) throw e
            error = friendlyError(e)
        }
    }
    LaunchedEffect(ref, owner) {
        owner.lifecycle.repeatOnLifecycle(Lifecycle.State.STARTED) { load() }
    }
    fun run(id: String, task: suspend () -> Unit) {
        if (busy != null) return
        busy = id
        scope.launch {
            try {
                error = null
                task()
                load()
            } catch (e: Exception) {
                if (e is CancellationException) throw e
                error = friendlyError(e)
            } finally {
                busy = null
            }
        }
    }
    val picker =
        rememberLauncherForActivityResult(ActivityResultContracts.OpenDocument()) { uri ->
            if (uri != null)
                run("skill") {
                    val file = model.importFile(uri)
                    skillFile = file
                    preview = model.previewSkill(ref, file)
                }
        }
    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text("Сервисы и навыки") },
                navigationIcon = { BackButton(back) },
                actions = {
                    IconButton(enabled = busy == null, onClick = { scope.launch { load() } }) {
                        Icon(Icons.Rounded.Refresh, "Обновить")
                    }
                    if (canManage)
                        Box {
                            IconButton(onClick = { add = true }) {
                                Icon(Icons.Rounded.Add, "Добавить")
                            }
                            DropdownMenu(add, { add = false }) {
                                DropdownMenuItem(
                                    text = { Text("Сервис по ссылке MCP") },
                                    onClick = {
                                        add = false
                                        mcp = true
                                    },
                                )
                                DropdownMenuItem(
                                    text = { Text("Навык из SKILL.md") },
                                    onClick = {
                                        add = false
                                        picker.launch(arrayOf("text/*", "application/octet-stream"))
                                    },
                                )
                            }
                        }
                },
            )
        }
    ) { insets ->
        LazyColumn(Modifier.fillMaxSize().consumeWindowInsets(insets), contentPadding = insets) {
            item {
                Text(
                    "Доступно сотруднику в этой переписке.",
                    Modifier.padding(20.dp),
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
            if (busy != null || data == null && error == null)
                item { LinearProgressIndicator(Modifier.fillMaxWidth()) }
            error?.let {
                item { Text(it, Modifier.padding(20.dp), color = MaterialTheme.colorScheme.error) }
            }
            data?.string("notice")?.let {
                item {
                    Text(it, Modifier.padding(20.dp), style = MaterialTheme.typography.bodySmall)
                }
            }
            items(
                data?.objects("connections") ?: emptyList(),
                key = { "service:" + it.getString("id") },
            ) { c ->
                ListItem(
                    headlineContent = { Text(c.getString("name")) },
                    supportingContent = {
                        Text(
                            c.string("detail") ?: if (c.optBoolean("connected")) "Подключён" else ""
                        )
                    },
                    leadingContent = { Icon(Icons.Rounded.Link, null) },
                    trailingContent = {
                        if (c.optBoolean("connected"))
                            Icon(
                                Icons.Rounded.Check,
                                "Подключён",
                                tint = MaterialTheme.colorScheme.primary,
                            )
                        else if (canManage)
                            TextButton(
                                enabled = busy == null,
                                onClick = {
                                    run(c.getString("id")) {
                                        val url = model.connectService(ref, c.getString("id"))
                                        if (url != null) {
                                            val uri = Uri.parse(url)
                                            require(uri.scheme == "https" && uri.host != null)
                                            context.startActivity(Intent(Intent.ACTION_VIEW, uri))
                                        }
                                    }
                                },
                            ) {
                                Text("Подключить")
                            }
                    },
                )
            }
            if (extensions?.objects("items")?.isNotEmpty() == true)
                item {
                    Text(
                        "Навыки и расширения",
                        Modifier.padding(20.dp),
                        style = MaterialTheme.typography.titleMedium,
                    )
                }
            items(
                extensions?.objects("items") ?: emptyList(),
                key = { "extension:" + it.getString("id") },
            ) { e ->
                ListItem(
                    headlineContent = { Text(e.getString("name")) },
                    supportingContent = { Text(e.optString("description")) },
                    trailingContent = {
                        Switch(
                            checked = e.optBoolean("enabled"),
                            enabled = canManage && busy == null,
                            onCheckedChange = { value ->
                                run(e.getString("id")) {
                                    model.changeExtension(ref, e.getString("id"), value)
                                }
                            },
                        )
                    },
                )
            }
            if (!canManage)
                item {
                    Text(
                        "Новые сервисы подключает владелец устройства.",
                        Modifier.padding(20.dp),
                        style = MaterialTheme.typography.bodySmall,
                    )
                }
            item { Spacer(Modifier.height(20.dp)) }
        }
    }
    if (mcp)
        McpDialog(busy != null, { mcp = false }) { name, url, token ->
            run("mcp") {
                model.addMcp(ref, name, url, token)
                mcp = false
            }
        }
    preview?.let { p ->
        AlertDialog(
            onDismissRequest = {
                preview = null
                skillFile = null
            },
            title = { Text("Добавить «${p.optString("name")}»?") },
            text = { Text(p.optString("description")) },
            confirmButton = {
                TextButton(
                    enabled = busy == null,
                    onClick = {
                        run("install") {
                            model.installSkill(ref, requireNotNull(skillFile), p)
                            preview = null
                            skillFile = null
                        }
                    },
                ) {
                    Text("Добавить")
                }
            },
            dismissButton = {
                TextButton(
                    onClick = {
                        preview = null
                        skillFile = null
                    }
                ) {
                    Text("Отмена")
                }
            },
        )
    }
}

@Composable
private fun McpDialog(busy: Boolean, dismiss: () -> Unit, save: (String, String, String) -> Unit) {
    var name by remember { mutableStateOf("") }
    var url by remember { mutableStateOf("") }
    var token by remember { mutableStateOf("") }
    AlertDialog(
        onDismissRequest = dismiss,
        title = { Text("Добавить сервис") },
        text = {
            Column(
                Modifier.verticalScroll(rememberScrollState()),
                verticalArrangement = Arrangement.spacedBy(12.dp),
            ) {
                OutlinedTextField(
                    name,
                    { name = it },
                    label = { Text("Название") },
                    singleLine = true,
                )
                OutlinedTextField(
                    url,
                    { url = it },
                    label = { Text("Адрес MCP") },
                    placeholder = { Text("https://…") },
                    singleLine = true,
                )
                OutlinedTextField(
                    token,
                    { token = it },
                    label = { Text("Ключ, если нужен") },
                    visualTransformation = PasswordVisualTransformation(),
                    singleLine = true,
                )
            }
        },
        confirmButton = {
            TextButton(
                enabled = !busy && name.isNotBlank() && url.startsWith("https://"),
                onClick = { save(name.trim(), url.trim(), token.trim()) },
            ) {
                Text(if (busy) "Подключаем…" else "Подключить")
            }
        },
        dismissButton = { TextButton(enabled = !busy, onClick = dismiss) { Text("Отмена") } },
    )
}

@Composable
fun SchedulesScreen(model: HomeViewModel, ref: ChatRef, back: () -> Unit) {
    var data by remember { mutableStateOf<JSONObject?>(null) }
    var error by remember { mutableStateOf<String?>(null) }
    var busy by remember { mutableStateOf<String?>(null) }
    val scope = rememberCoroutineScope()
    suspend fun load() {
        try {
            error = null
            data = model.schedules(ref)
        } catch (e: Exception) {
            if (e is CancellationException) throw e
            error = friendlyError(e)
        }
    }
    LaunchedEffect(ref) { load() }
    Scaffold(
        topBar = {
            TopAppBar(title = { Text("Расписание") }, navigationIcon = { BackButton(back) })
        }
    ) { insets ->
        LazyColumn(Modifier.fillMaxSize().consumeWindowInsets(insets), contentPadding = insets) {
            item {
                Text(
                    "Напишите в чате, о чём и когда напомнить. Здесь можно проверить результат или остановить задачу.",
                    Modifier.padding(20.dp),
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
            error?.let {
                item {
                    TextButton(
                        onClick = { scope.launch { load() } },
                        modifier = Modifier.padding(12.dp),
                    ) {
                        Text(it)
                    }
                }
            }
            if (data == null && error == null)
                item { LinearProgressIndicator(Modifier.fillMaxWidth()) }
            items(data?.objects("schedules") ?: emptyList(), key = { it.getString("id") }) { s ->
                val result = if (!s.optBoolean("enabled") && s.optString("cron").startsWith("@once "))
                    when (s.optString("lastRunStatus")) {
                        "completed", "quiet" -> "Выполнено"
                        "running" -> "Выполняется"
                        "ready" -> "Ожидает доставки"
                        "failed" -> "Не выполнено"
                        "skipped" -> "Пропущено"
                        "uncertain" -> "Проверьте результат"
                        else -> null
                    } else null
                val next = runCatching {
                    Instant.parse(s.getString("nextRunAt"))
                        .atZone(ZoneId.of(s.getString("timezone")))
                        .format(DateTimeFormatter.ofPattern("d MMM, HH:mm z"))
                }
                    .getOrDefault(s.optString("timezone"))
                ListItem(
                    headlineContent = { Text(s.getString("name")) },
                    supportingContent = {
                        Text(
                            if (result != null) "$result · $next"
                            else if (s.optBoolean("enabled")) "Следующий запуск: $next"
                            else "Приостановлено"
                        )
                    },
                    trailingContent = {
                        if (result == null) Switch(
                            checked = s.optBoolean("enabled"),
                            enabled = busy == null,
                            onCheckedChange = {
                                busy = s.getString("id")
                                scope.launch {
                                    try {
                                        model.toggleSchedule(ref, s)
                                        load()
                                    } catch (e: Exception) {
                                        if (e is CancellationException) throw e
                                        error = friendlyError(e)
                                    } finally {
                                        busy = null
                                    }
                                }
                            },
                        )
                    },
                )
            }
            if (data != null && data!!.objects("schedules").isEmpty())
                item {
                    Text(
                        "Расписаний пока нет",
                        Modifier.padding(20.dp),
                        style = MaterialTheme.typography.titleMedium,
                    )
                }
        }
    }
}
