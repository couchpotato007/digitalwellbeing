package io.github.couchpotato007.wellbeing

import androidx.activity.compose.BackHandler
import androidx.compose.animation.AnimatedContent
import androidx.compose.animation.core.tween
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.slideInHorizontally
import androidx.compose.animation.slideOutHorizontally
import androidx.compose.animation.togetherWith
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.Search
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.Card
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExtendedFloatingActionButton
import androidx.compose.material3.FilterChip
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.InputChip
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.RadioButton
import androidx.compose.material3.Surface
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

/**
 * The server's categories as a list grouped by top level, with search, and
 * an editor for one. [onChanged] is called after anything was saved, the
 * server has then put all events in categories again.
 */
@Composable
fun CategoriesScreen(server: Server, onBack: () -> Unit, onChanged: () -> Unit) {
    var overview by remember { mutableStateOf<CategoryOverview?>(null) }
    var error by remember { mutableStateOf<String?>(null) }
    var reload by remember { mutableIntStateOf(0) }
    // the rule in the editor, null for the list
    var editing by remember { mutableStateOf<Rule?>(null) }

    LaunchedEffect(reload) {
        withContext(Dispatchers.IO) { runCatching { CategoriesApi.load(server) } }
            .onSuccess {
                overview = it
                error = null
            }
            .onFailure { error = Sync.describe(it) }
    }
    val changed = {
        reload++
        onChanged()
    }

    AnimatedContent(
        editing,
        transitionSpec = {
            // the editor comes in from the right and goes back there
            val forward = targetState != null
            (slideInHorizontally(tween(280)) { if (forward) it else -it / 3 } + fadeIn(tween(280))) togetherWith
                (slideOutHorizontally(tween(250)) { if (forward) -it / 3 else it } + fadeOut(tween(250)))
        },
        contentKey = { it == null },
        label = "categories",
    ) { rule ->
        val current = overview
        if (rule == null || current == null) {
            BackHandler(onBack = onBack)
            CategoryList(
                server,
                current,
                error,
                onBack = onBack,
                onOpen = { editing = it },
                onChanged = changed,
                onRetry = { reload++ },
            )
        } else {
            CategoryEditor(server, rule, current, onClose = { saved ->
                editing = null
                if (saved) changed()
            })
        }
    }
}

@Composable
private fun TopBar(title: String, onBack: () -> Unit, actions: @Composable () -> Unit = {}) {
    Row(Modifier.fillMaxWidth().padding(4.dp), verticalAlignment = Alignment.CenterVertically) {
        IconButton(onClick = onBack) { Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "Back") }
        Text(
            title,
            style = MaterialTheme.typography.titleLarge,
            maxLines = 1,
            overflow = TextOverflow.Ellipsis,
            modifier = Modifier.weight(1f),
        )
        actions()
    }
}

/** The color of a category's top level, like on the dashboard. */
@Composable
private fun groupColor(order: List<String>, name: String): Color = categoryColor(order, name)

@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun CategoryList(
    server: Server,
    overview: CategoryOverview?,
    error: String?,
    onBack: () -> Unit,
    onOpen: (Rule) -> Unit,
    onChanged: () -> Unit,
    onRetry: () -> Unit,
) {
    var query by remember { mutableStateOf("") }
    // the uncategorized app or title to put into a category
    var assigning by remember { mutableStateOf<UsageItem?>(null) }

    Box(Modifier.fillMaxSize()) {
        Column(Modifier.fillMaxSize()) {
            TopBar("Categories", onBack)
            OutlinedTextField(
                query, { query = it },
                placeholder = { Text("Search categories and patterns") },
                leadingIcon = { Icon(Icons.Filled.Search, contentDescription = null) },
                trailingIcon = {
                    if (query.isNotEmpty()) {
                        IconButton(onClick = { query = "" }) { Icon(Icons.Filled.Close, contentDescription = "Clear") }
                    }
                },
                singleLine = true,
                shape = RoundedCornerShape(28.dp),
                modifier = Modifier.fillMaxWidth().padding(horizontal = 16.dp),
            )

            when {
                overview == null && error != null -> Column(Modifier.padding(16.dp)) {
                    Text("Could not load the categories: $error")
                    TextButton(onClick = onRetry) { Text("Retry") }
                }
                overview == null -> Box(Modifier.fillMaxWidth().padding(32.dp), contentAlignment = Alignment.Center) {
                    CircularProgressIndicator()
                }
                else -> {
                    val term = query.trim().lowercase()
                    val shown = overview.rules.filter { rule ->
                        term.isEmpty() || rule.name.lowercase().contains(term) ||
                            rule.patterns.any { it.lowercase().contains(term) }
                    }
                    val groups = shown.groupBy { topLevel(it.name) }
                    // in the colors' order, the rest by name
                    val names = overview.categoryOrder.filter { it in groups } +
                        groups.keys.filter { it !in overview.categoryOrder }.sorted()

                    LazyColumn(
                        contentPadding = PaddingValues(start = 16.dp, end = 16.dp, top = 12.dp, bottom = 96.dp),
                        verticalArrangement = Arrangement.spacedBy(12.dp),
                    ) {
                        items(names, key = { "group-$it" }) { group ->
                            val rules = groups.getValue(group).sortedBy { it.name }
                            CategoryGroup(group, groupColor(overview.categoryOrder, group), rules, onOpen)
                        }
                        if (names.isEmpty()) {
                            item { Text("No category matches \"$query\".", color = MaterialTheme.colorScheme.onSurfaceVariant) }
                        }
                        val uncategorized = (overview.uncategorizedApps + overview.uncategorizedTitles)
                            .filter { term.isEmpty() || it.name.lowercase().contains(term) }
                        if (uncategorized.isNotEmpty()) {
                            item(key = "uncategorized") {
                                UncategorizedCard(uncategorized, onAssign = { assigning = it })
                            }
                        }
                    }
                }
            }
        }

        if (overview != null) {
            ExtendedFloatingActionButton(
                onClick = { onOpen(Rule(0, "", emptyList(), true, emptyList())) },
                icon = { Icon(Icons.Filled.Add, contentDescription = null) },
                text = { Text("New category") },
                modifier = Modifier.align(Alignment.BottomEnd).padding(16.dp),
            )
        }
    }

    val item = assigning
    if (item != null && overview != null) {
        AssignDialog(
            server,
            item,
            overview.rules,
            onDismiss = { assigning = null },
            onAssigned = {
                assigning = null
                onChanged()
            },
            onNew = {
                assigning = null
                onOpen(Rule(0, "", listOf(escapePattern(item.name)), true, emptyList()))
            },
        )
    }
}

/** A top level with its rules, each with a few of its patterns. */
@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun CategoryGroup(group: String, color: Color, rules: List<Rule>, onOpen: (Rule) -> Unit) {
    val muted = MaterialTheme.colorScheme.onSurfaceVariant
    Card {
        Column(Modifier.padding(vertical = 8.dp)) {
            Row(Modifier.padding(horizontal = 16.dp, vertical = 8.dp), verticalAlignment = Alignment.CenterVertically) {
                Box(Modifier.size(12.dp).background(color, CircleShape))
                Text(group, style = MaterialTheme.typography.titleMedium, modifier = Modifier.weight(1f).padding(start = 10.dp))
                Text(formatDuration(rules.sumOf { it.ms }), style = MaterialTheme.typography.labelLarge, color = muted)
            }
            rules.forEach { rule ->
                val parts = rule.name.split(" > ")
                HorizontalDivider(Modifier.padding(start = 16.dp))
                Column(
                    Modifier
                        .fillMaxWidth()
                        .clickable { onOpen(rule) }
                        .padding(start = 16.dp + 16.dp * (parts.size - 1), end = 16.dp, top = 10.dp, bottom = 10.dp),
                    verticalArrangement = Arrangement.spacedBy(6.dp),
                ) {
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Text(parts.last(), style = MaterialTheme.typography.bodyLarge, modifier = Modifier.weight(1f))
                        Text(formatDuration(rule.ms), style = MaterialTheme.typography.bodyMedium, color = muted)
                    }
                    FlowRow(horizontalArrangement = Arrangement.spacedBy(4.dp), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                        rule.patterns.take(5).forEach { PatternPill(it) }
                        if (rule.patterns.size > 5) PatternPill("+${rule.patterns.size - 5}", monospace = false)
                        if (rule.devices.isNotEmpty()) {
                            Text(
                                "only " + rule.devices.joinToString(", "),
                                style = MaterialTheme.typography.labelSmall,
                                color = muted,
                                modifier = Modifier.padding(start = 4.dp),
                            )
                        }
                    }
                }
            }
        }
    }
}

@Composable
private fun PatternPill(text: String, monospace: Boolean = true) {
    Surface(shape = RoundedCornerShape(50), color = MaterialTheme.colorScheme.surfaceVariant) {
        Text(
            if (text.length > 24) text.take(22) + "…" else text,
            style = MaterialTheme.typography.labelSmall.copy(fontFamily = if (monospace) FontFamily.Monospace else FontFamily.Default),
            color = MaterialTheme.colorScheme.onSurfaceVariant,
            maxLines = 1,
            modifier = Modifier.padding(horizontal = 8.dp, vertical = 2.dp),
        )
    }
}

@Composable
private fun UncategorizedCard(items: List<UsageItem>, onAssign: (UsageItem) -> Unit) {
    Card {
        Column(Modifier.padding(vertical = 8.dp)) {
            Text(
                "Without a category · 30 days",
                style = MaterialTheme.typography.titleMedium,
                modifier = Modifier.padding(horizontal = 16.dp, vertical = 8.dp),
            )
            Text(
                "Tap one to add it to a category.",
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                modifier = Modifier.padding(horizontal = 16.dp),
            )
            items.forEach { item ->
                HorizontalDivider(Modifier.padding(start = 16.dp, top = 8.dp))
                Row(
                    Modifier.fillMaxWidth().clickable { onAssign(item) }.padding(horizontal = 16.dp, vertical = 10.dp),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    Column(Modifier.weight(1f)) {
                        Text(item.name, maxLines = 1, overflow = TextOverflow.Ellipsis)
                        if (item.detail.isNotEmpty()) {
                            Text(
                                item.detail,
                                style = MaterialTheme.typography.bodySmall,
                                color = MaterialTheme.colorScheme.onSurfaceVariant,
                                maxLines = 1,
                            )
                        }
                    }
                    Text(formatDuration(item.ms), Modifier.padding(start = 12.dp))
                    Icon(Icons.Filled.Add, contentDescription = "Add to a category", Modifier.padding(start = 8.dp))
                }
            }
        }
    }
}

/** Picks the category an uncategorized app or title goes into. */
@Composable
private fun AssignDialog(
    server: Server,
    item: UsageItem,
    rules: List<Rule>,
    onDismiss: () -> Unit,
    onAssigned: () -> Unit,
    onNew: () -> Unit,
) {
    val scope = rememberCoroutineScope()
    // one rule per name, the first gets the pattern
    val choices = rules.distinctBy { it.name }.sortedBy { it.name }
    var picked by remember { mutableStateOf<Rule?>(null) }
    var saving by remember { mutableStateOf(false) }
    var error by remember { mutableStateOf<String?>(null) }

    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text("Add \"${item.name}\" to") },
        text = {
            Column(Modifier.verticalScroll(rememberScrollState())) {
                choices.forEach { rule ->
                    Row(
                        Modifier.fillMaxWidth().clickable { picked = rule }.padding(vertical = 2.dp),
                        verticalAlignment = Alignment.CenterVertically,
                    ) {
                        RadioButton(selected = picked == rule, onClick = { picked = rule })
                        Text(rule.name)
                    }
                }
                TextButton(onClick = onNew) { Text("New category with it…") }
                error?.let { Text(it, color = MaterialTheme.colorScheme.error) }
            }
        },
        confirmButton = {
            TextButton(
                enabled = picked != null && !saving,
                onClick = {
                    val rule = picked ?: return@TextButton
                    saving = true
                    scope.launch {
                        withContext(Dispatchers.IO) { runCatching { CategoriesApi.assign(server, rule.id, item.name) } }
                            .onSuccess { onAssigned() }
                            .onFailure { error = Sync.describe(it) }
                        saving = false
                    }
                },
            ) { Text(if (saving) "Adding…" else "Add") }
        },
        dismissButton = { TextButton(onClick = onDismiss) { Text("Cancel") } },
    )
}

/**
 * One rule: its name with the existing ones to put it under, its patterns as
 * chips, ignore case, devices, and what it matches, updated while typing.
 * [onClose] gets whether it was saved or deleted.
 */
@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun CategoryEditor(server: Server, rule: Rule, overview: CategoryOverview, onClose: (Boolean) -> Unit) {
    val scope = rememberCoroutineScope()
    var name by remember { mutableStateOf(rule.name) }
    var patterns by remember { mutableStateOf(rule.patterns) }
    var input by remember { mutableStateOf("") }
    var ignoreCase by remember { mutableStateOf(rule.ignoreCase) }
    var devices by remember { mutableStateOf(rule.devices) }
    var saving by remember { mutableStateOf(false) }
    var error by remember { mutableStateOf<String?>(null) }
    var confirmDelete by remember { mutableStateOf(false) }
    var confirmDiscard by remember { mutableStateOf(false) }

    // a pattern still in the field counts too
    val all = (patterns + input.trim()).filter { it.isNotEmpty() }
    val edited = rule.copy(name = name.trim(), patterns = all, ignoreCase = ignoreCase, devices = devices)
    val dirty = edited.copy(ms = 0) != rule.copy(ms = 0)
    val back = { if (dirty) confirmDiscard = true else onClose(false) }
    BackHandler(onBack = back)

    val addInput = {
        val text = input.trim()
        if (text.isNotEmpty() && text !in patterns) patterns = patterns + text
        input = ""
    }
    val save: () -> Unit = save@{
        if (edited.name.isEmpty()) {
            error = "The category needs a name"
            return@save
        }
        if (all.isEmpty()) {
            error = "The category needs at least one pattern"
            return@save
        }
        saving = true
        scope.launch {
            withContext(Dispatchers.IO) { runCatching { CategoriesApi.save(server, edited) } }
                .onSuccess { onClose(true) }
                .onFailure { error = Sync.describe(it) }
            saving = false
        }
    }

    Column(Modifier.fillMaxSize().imePadding()) {
        TopBar(if (rule.id == 0) "New category" else rule.name, onBack = back) {
            TextButton(enabled = !saving && dirty, onClick = save) { Text(if (saving) "Saving…" else "Save") }
        }
        Column(
            Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(horizontal = 16.dp, vertical = 8.dp),
            verticalArrangement = Arrangement.spacedBy(16.dp),
        ) {
            error?.let {
                Surface(color = MaterialTheme.colorScheme.errorContainer, shape = RoundedCornerShape(12.dp)) {
                    Text(
                        it,
                        color = MaterialTheme.colorScheme.onErrorContainer,
                        modifier = Modifier.fillMaxWidth().padding(12.dp),
                    )
                }
            }

            Section("Name") {
                OutlinedTextField(
                    name, { name = it },
                    placeholder = { Text("Work > Programming") },
                    supportingText = { Text("Use > for subcategories, the deepest matching one wins") },
                    singleLine = true,
                    modifier = Modifier.fillMaxWidth(),
                )
                // existing categories to put this one under
                val parents = overview.rules.map { it.name }.distinct().sorted().filter { it != rule.name }
                if (parents.isNotEmpty()) {
                    Text("Put under", style = MaterialTheme.typography.labelMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
                    Row(Modifier.horizontalScroll(rememberScrollState()), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        parents.forEach { parent ->
                            val own = name.split(">").last().trim()
                            FilterChip(
                                selected = name.trim().startsWith("$parent >"),
                                onClick = { name = "$parent > $own" },
                                label = { Text(parent) },
                            )
                        }
                    }
                }
            }

            Section("Patterns") {
                Text(
                    "Each one is matched against the app and the window title (the domain and tab title for " +
                        "browser tabs). Plain words work, they are regular expressions: \\b is a word boundary, " +
                        "^x\\.com$ matches exactly x.com. Tap a pattern to edit it.",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
                FlowRow(horizontalArrangement = Arrangement.spacedBy(6.dp), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                    patterns.forEach { pattern ->
                        InputChip(
                            selected = false,
                            onClick = {
                                // back into the field to edit, the one there becomes a chip
                                addInput()
                                patterns = patterns - pattern
                                input = pattern
                            },
                            label = {
                                Text(pattern, fontFamily = FontFamily.Monospace, maxLines = 1, overflow = TextOverflow.Ellipsis)
                            },
                            trailingIcon = {
                                Icon(
                                    Icons.Filled.Close,
                                    contentDescription = "Remove",
                                    modifier = Modifier.size(18.dp).clickable { patterns = patterns - pattern },
                                )
                            },
                        )
                    }
                }
                OutlinedTextField(
                    input, { input = it },
                    placeholder = { Text("Add a pattern, like spotify") },
                    singleLine = true,
                    textStyle = MaterialTheme.typography.bodyLarge.copy(fontFamily = FontFamily.Monospace),
                    keyboardOptions = KeyboardOptions(imeAction = ImeAction.Done),
                    keyboardActions = KeyboardActions(onDone = { addInput() }),
                    trailingIcon = {
                        IconButton(enabled = input.isNotBlank(), onClick = addInput) {
                            Icon(Icons.Filled.Add, contentDescription = "Add pattern")
                        }
                    },
                    modifier = Modifier.fillMaxWidth(),
                )
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Text("Ignore upper and lower case", Modifier.weight(1f))
                    Switch(checked = ignoreCase, onCheckedChange = { ignoreCase = it })
                }
            }

            if (overview.devices.isNotEmpty()) {
                Section("Devices") {
                    Text(
                        if (devices.isEmpty()) "On all devices, or pick some" else "Only on the ones picked",
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                    FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        overview.devices.forEach { device ->
                            FilterChip(
                                selected = device in devices,
                                onClick = { devices = if (device in devices) devices - device else devices + device },
                                label = { Text(device) },
                            )
                        }
                    }
                }
            }

            MatchPreview(server, edited)

            if (rule.id != 0) {
                OutlinedButton(
                    onClick = { confirmDelete = true },
                    colors = ButtonDefaults.outlinedButtonColors(contentColor = MaterialTheme.colorScheme.error),
                    modifier = Modifier.fillMaxWidth(),
                ) { Text("Delete category") }
            }
            Spacer(Modifier.height(24.dp))
        }
    }

    if (confirmDelete) {
        AlertDialog(
            onDismissRequest = { confirmDelete = false },
            title = { Text("Delete \"${rule.name}\"?") },
            text = { Text("What it matched gets the next fitting category, or none.") },
            confirmButton = {
                TextButton(onClick = {
                    confirmDelete = false
                    scope.launch {
                        withContext(Dispatchers.IO) { runCatching { CategoriesApi.delete(server, rule.id) } }
                            .onSuccess { onClose(true) }
                            .onFailure { error = Sync.describe(it) }
                    }
                }) { Text("Delete") }
            },
            dismissButton = { TextButton(onClick = { confirmDelete = false }) { Text("Cancel") } },
        )
    }
    if (confirmDiscard) {
        AlertDialog(
            onDismissRequest = { confirmDiscard = false },
            title = { Text("Discard changes?") },
            confirmButton = {
                TextButton(onClick = {
                    confirmDiscard = false
                    onClose(false)
                }) { Text("Discard") }
            },
            dismissButton = { TextButton(onClick = { confirmDiscard = false }) { Text("Keep editing") } },
        )
    }
}

@Composable
private fun Section(title: String, content: @Composable () -> Unit) {
    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
        Text(title, style = MaterialTheme.typography.titleSmall, color = MaterialTheme.colorScheme.primary)
        content()
    }
}

/** What [rule] would match in the last 30 days, asked again a moment after each change. */
@Composable
private fun MatchPreview(server: Server, rule: Rule) {
    var preview by remember { mutableStateOf<Preview?>(null) }
    var error by remember { mutableStateOf<String?>(null) }
    var loading by remember { mutableStateOf(false) }
    LaunchedEffect(rule.patterns, rule.ignoreCase, rule.devices) {
        if (rule.patterns.isEmpty()) {
            preview = null
            error = null
            return@LaunchedEffect
        }
        delay(400)
        loading = true
        // the server needs a name, which doesn't change what matches
        val asked = rule.copy(name = rule.name.ifEmpty { "Preview" })
        withContext(Dispatchers.IO) { runCatching { CategoriesApi.preview(server, asked) } }
            .onSuccess {
                preview = it
                error = null
            }
            .onFailure { error = Sync.describe(it) }
        loading = false
    }

    Card {
        Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text("Matches in the last 30 days", style = MaterialTheme.typography.titleSmall, modifier = Modifier.weight(1f))
                if (loading) CircularProgressIndicator(Modifier.size(16.dp), strokeWidth = 2.dp)
            }
            val current = preview
            when {
                rule.patterns.isEmpty() -> Text(
                    "Add a pattern to see what it matches.",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
                error != null -> Text(error!!, color = MaterialTheme.colorScheme.error, style = MaterialTheme.typography.bodyMedium)
                current == null -> {}
                current.apps.isEmpty() -> Text(
                    "Nothing yet.",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
                else -> {
                    Text(formatDuration(current.screenMs) + " screen time", style = MaterialTheme.typography.headlineSmall)
                    MatchList("Apps and domains", current.apps)
                    MatchList("Window titles", current.titles)
                }
            }
        }
    }
}

@Composable
private fun MatchList(title: String, items: List<UsageItem>) {
    if (items.isEmpty()) return
    Text(title, style = MaterialTheme.typography.labelLarge, color = MaterialTheme.colorScheme.onSurfaceVariant)
    items.take(6).forEach { item ->
        Row {
            Text(item.name, maxLines = 1, overflow = TextOverflow.Ellipsis, modifier = Modifier.weight(1f))
            Text(formatDuration(item.ms), Modifier.padding(start = 12.dp), style = MaterialTheme.typography.bodyMedium)
        }
    }
    if (items.size > 6) {
        Text("and ${items.size - 6} more", style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
    }
}
