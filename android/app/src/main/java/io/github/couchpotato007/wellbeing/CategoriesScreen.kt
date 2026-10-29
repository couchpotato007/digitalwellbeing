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
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.Card
import androidx.compose.material3.Checkbox
import androidx.compose.material3.FilterChip
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.SegmentedButton
import androidx.compose.material3.SegmentedButtonDefaults
import androidx.compose.material3.SingleChoiceSegmentedButtonRow
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

/** What the categories screen shows: the list, a category, or a rule of one. */
private sealed interface Page {
    data object List : Page
    data class Open(val name: String) : Page
    data class EditRule(val rule: Rule) : Page
}

/**
 * The categories: what has no category yet on top, to sort with a tap, then
 * every category with its rating and what is in it. A category opens to
 * rename it, rate it, move its apps and websites, and for advanced rules.
 */
@Composable
fun CategoriesScreen(server: Server, onBack: () -> Unit, onChanged: () -> Unit) {
    val scope = rememberCoroutineScope()
    var overview by remember { mutableStateOf<CategoryOverview?>(null) }
    var error by remember { mutableStateOf<String?>(null) }
    var busy by remember { mutableStateOf(false) }
    var reload by remember { mutableIntStateOf(0) }
    var page by remember { mutableStateOf<Page>(Page.List) }
    // an app or website to move, with the category it is in ("" for none)
    var moving by remember { mutableStateOf<Pair<CategoryItem, String>?>(null) }
    // the new category dialog, with what goes into it if anything
    var creating by remember { mutableStateOf<CategoryItem?>(null) }
    var creatingOpen by remember { mutableStateOf(false) }

    LaunchedEffect(reload) {
        withContext(Dispatchers.IO) { runCatching { CategoriesApi.load(server) } }
            .onSuccess {
                overview = it
                error = null
            }
            .onFailure { error = Sync.describe(it) }
        busy = false
    }
    /** Runs a change on the server, then loads everything again. */
    val change = { action: () -> Unit ->
        busy = true
        scope.launch {
            withContext(Dispatchers.IO) { runCatching(action) }
                .onFailure { error = Sync.describe(it) }
            reload++
            onChanged()
        }
        Unit
    }

    AnimatedContent(
        page,
        transitionSpec = {
            val forward = depth(targetState) > depth(initialState)
            (slideInHorizontally(tween(280)) { if (forward) it else -it / 3 } + fadeIn(tween(280))) togetherWith
                (slideOutHorizontally(tween(250)) { if (forward) -it / 3 else it } + fadeOut(tween(250)))
        },
        label = "categories",
    ) { shown ->
        val current = overview
        Column(Modifier.fillMaxSize()) {
            when (shown) {
                Page.List -> {
                    BackHandler(onBack = onBack)
                    TopBar("Categories", onBack)
                }
                is Page.Open -> {
                    BackHandler { page = Page.List }
                    TopBar(shown.name, { page = Page.List })
                }
                is Page.EditRule -> {
                    BackHandler { page = Page.Open(shown.rule.category) }
                    TopBar(if (shown.rule.id == 0) "New rule" else "Rule", { page = Page.Open(shown.rule.category) })
                }
            }
            if (busy) LinearProgressIndicator(Modifier.fillMaxWidth()) else Box(Modifier.heightIn(min = 4.dp))
            error?.let {
                Text(it, color = MaterialTheme.colorScheme.error, modifier = Modifier.padding(horizontal = 16.dp))
            }
            if (current == null) {
                if (error != null) TextButton(onClick = { reload++ }, Modifier.padding(8.dp)) { Text("Retry") }
                return@Column
            }
            when (shown) {
                Page.List -> ListPage(
                    current,
                    onOpen = { page = Page.Open(it.name) },
                    onMove = { moving = it to "" },
                    onNew = { creatingOpen = true },
                    onAddBuiltins = { change { CategoriesApi.addBuiltins(server) } },
                )
                is Page.Open -> {
                    val category = current.categories.find { it.name == shown.name }
                    if (category == null) {
                        // deleted or renamed elsewhere
                        LaunchedEffect(Unit) { page = Page.List }
                    } else {
                        CategoryPage(
                            current,
                            category,
                            onSave = { name, rating ->
                                change { CategoriesApi.save(server, name, rating, category.name) }
                                page = Page.Open(name)
                            },
                            onDelete = {
                                change { CategoriesApi.delete(server, category.name) }
                                page = Page.List
                            },
                            onMove = { moving = it to category.name },
                            onRule = { page = Page.EditRule(it) },
                        )
                    }
                }
                is Page.EditRule -> RulePage(
                    server,
                    shown.rule,
                    current.devices,
                    onSave = {
                        change { CategoriesApi.saveRule(server, it) }
                        page = Page.Open(shown.rule.category)
                    },
                    onDelete = {
                        change { CategoriesApi.deleteRule(server, shown.rule.id) }
                        page = Page.Open(shown.rule.category)
                    },
                )
            }
        }
    }

    moving?.let { (item, from) ->
        MoveDialog(
            item,
            from,
            overview?.categories.orEmpty(),
            overview?.categoryOrder.orEmpty(),
            onPick = { to ->
                moving = null
                change { CategoriesApi.assign(server, item.name, to) }
            },
            onNew = {
                moving = null
                creating = item
                creatingOpen = true
            },
            onDismiss = { moving = null },
        )
    }
    if (creatingOpen) {
        NewCategoryDialog(
            item = creating,
            onCreate = { name, rating ->
                val item = creating
                creatingOpen = false
                creating = null
                change {
                    CategoriesApi.save(server, name, rating)
                    if (item != null) CategoriesApi.assign(server, item.name, name)
                }
            },
            onDismiss = {
                creatingOpen = false
                creating = null
            },
        )
    }
}

private fun depth(page: Page) = when (page) {
    Page.List -> 0
    is Page.Open -> 1
    is Page.EditRule -> 2
}

@Composable
private fun TopBar(title: String, onBack: () -> Unit) {
    Row(Modifier.fillMaxWidth().padding(4.dp), verticalAlignment = Alignment.CenterVertically) {
        IconButton(onClick = onBack) { Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "Back") }
        Text(
            title,
            style = MaterialTheme.typography.titleLarge,
            maxLines = 1,
            overflow = TextOverflow.Ellipsis,
            modifier = Modifier.weight(1f),
        )
    }
}

@Composable
fun ratingColor(rating: Rating): Color = when (rating) {
    Rating.Productive -> Color(0xFF1BAF7A)
    Rating.Neutral -> MaterialTheme.colorScheme.outline
    Rating.Distracting -> Color(0xFFE34948)
}

@Composable
private fun RatingChip(rating: Rating) {
    val color = ratingColor(rating)
    Text(
        rating.label,
        style = MaterialTheme.typography.labelSmall,
        color = color,
        modifier = Modifier
            .clip(RoundedCornerShape(50))
            .background(color.copy(alpha = 0.12f))
            .padding(horizontal = 8.dp, vertical = 2.dp),
    )
}

/** Why an item is in its category, in words. */
private fun sourceText(item: CategoryItem) = listOfNotNull(
    when (item.source) {
        "assigned" -> "assigned by you"
        "rule" -> "by a rule"
        "known" -> "known app"
        "android" -> "by its Android app type"
        "browser" -> "in a browser"
        else -> null
    },
    item.devices.joinToString(", ").ifEmpty { null },
).joinToString(" · ")

@Composable
private fun ListPage(
    overview: CategoryOverview,
    onOpen: (Category) -> Unit,
    onMove: (CategoryItem) -> Unit,
    onNew: () -> Unit,
    onAddBuiltins: () -> Unit,
) {
    Column(
        Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(16.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        Text(
            "Most apps and websites get a category on their own: known ones, what Android says an app is, " +
                "and browser windows by the website shown. Times are of the last 30 days.",
            style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
        if (overview.unsorted.isNotEmpty()) {
            Card {
                Column(Modifier.padding(vertical = 12.dp)) {
                    Row(Modifier.padding(horizontal = 16.dp)) {
                        Text("Unsorted", style = MaterialTheme.typography.titleMedium, modifier = Modifier.weight(1f))
                        Text(formatDuration(overview.unsortedMs), style = MaterialTheme.typography.titleMedium)
                    }
                    Text(
                        "Tap one to give it a category",
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                        modifier = Modifier.padding(horizontal = 16.dp),
                    )
                    overview.unsorted.take(20).forEach { ItemRow(it) { onMove(it) } }
                }
            }
        }
        overview.categories.forEach { category ->
            Card(onClick = { onOpen(category) }) {
                Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
                    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        Box(
                            Modifier.size(12.dp).clip(CircleShape)
                                .background(categoryColor(overview.categoryOrder, category.name))
                        )
                        Text(
                            category.name,
                            style = MaterialTheme.typography.titleSmall,
                            maxLines = 1,
                            overflow = TextOverflow.Ellipsis,
                            modifier = Modifier.weight(1f, fill = false),
                        )
                        RatingChip(category.rating)
                        Box(Modifier.weight(1f))
                        Text(formatDuration(category.ms), style = MaterialTheme.typography.titleSmall)
                    }
                    Text(
                        category.items.take(4).joinToString(", ") { it.name }.ifEmpty { "Nothing in the last 30 days" },
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis,
                    )
                }
            }
        }
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            Button(onClick = onNew) { Text("New category") }
            OutlinedButton(onClick = onAddBuiltins) { Text("Restore built-in") }
        }
    }
}

/** An app or website with its time and why it is where it is. */
@Composable
private fun ItemRow(item: CategoryItem, onClick: () -> Unit) {
    Column(
        Modifier.fillMaxWidth().clickable(onClick = onClick).padding(horizontal = 16.dp, vertical = 10.dp),
    ) {
        Row {
            Text(item.name, maxLines = 1, overflow = TextOverflow.Ellipsis, modifier = Modifier.weight(1f))
            Text(formatDuration(item.ms), modifier = Modifier.padding(start = 12.dp))
        }
        val why = sourceText(item)
        if (why.isNotEmpty()) {
            Text(why, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
    }
}

@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun CategoryPage(
    overview: CategoryOverview,
    category: Category,
    onSave: (String, Rating) -> Unit,
    onDelete: () -> Unit,
    onMove: (CategoryItem) -> Unit,
    onRule: (Rule) -> Unit,
) {
    var name by remember(category) { mutableStateOf(category.name) }
    var rating by remember(category) { mutableStateOf(category.rating) }
    var confirmDelete by remember { mutableStateOf(false) }
    val changed = name.trim() != category.name || rating != category.rating

    Column(
        Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(16.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        Card {
            Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
                OutlinedTextField(
                    name, { name = it },
                    label = { Text("Name") },
                    supportingText = { Text("Use > for subcategories, like Work > Studying") },
                    singleLine = true,
                    modifier = Modifier.fillMaxWidth(),
                )
                Text("Counts as", style = MaterialTheme.typography.labelLarge)
                RatingPicker(rating) { rating = it }
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    Button(enabled = changed && name.isNotBlank(), onClick = { onSave(name.trim(), rating) }) { Text("Save") }
                    OutlinedButton(
                        onClick = { confirmDelete = true },
                        colors = ButtonDefaults.outlinedButtonColors(contentColor = MaterialTheme.colorScheme.error),
                    ) { Text("Delete") }
                }
            }
        }

        Card {
            Column(Modifier.padding(vertical = 12.dp)) {
                Row(Modifier.padding(horizontal = 16.dp)) {
                    Text("In this category", style = MaterialTheme.typography.titleMedium, modifier = Modifier.weight(1f))
                    Text(formatDuration(category.ms), style = MaterialTheme.typography.titleMedium)
                }
                Text(
                    "Tap one to move it",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    modifier = Modifier.padding(horizontal = 16.dp),
                )
                if (category.items.isEmpty()) {
                    Text(
                        "Nothing in the last 30 days.",
                        Modifier.padding(16.dp),
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
                category.items.forEach { ItemRow(it) { onMove(it) } }
            }
        }

        Card {
            Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                Text("Advanced rules", style = MaterialTheme.typography.titleMedium)
                Text(
                    "For what a whole app or website can't say, like window titles. Rules win over known apps, " +
                        "but not over what you assigned.",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
                category.rules.forEach { rule ->
                    Text(
                        rule.patterns.joinToString("  |  "),
                        fontFamily = FontFamily.Monospace,
                        style = MaterialTheme.typography.bodySmall,
                        maxLines = 2,
                        overflow = TextOverflow.Ellipsis,
                        modifier = Modifier
                            .fillMaxWidth()
                            .clip(RoundedCornerShape(8.dp))
                            .background(MaterialTheme.colorScheme.surfaceVariant)
                            .clickable { onRule(rule) }
                            .padding(10.dp),
                    )
                }
                TextButton(onClick = { onRule(Rule(0, category.name, emptyList())) }) { Text("+ Add rule") }
            }
        }
    }

    if (confirmDelete) {
        AlertDialog(
            onDismissRequest = { confirmDelete = false },
            title = { Text("Delete ${category.name}?") },
            text = {
                Text(
                    "Its rules go too, and what you assigned to it goes back to getting a category on its own." +
                        if (category.builtin) " Known apps of it stop counting for it, \"Restore built-in\" brings it back." else ""
                )
            },
            confirmButton = {
                TextButton(onClick = {
                    confirmDelete = false
                    onDelete()
                }) { Text("Delete") }
            },
            dismissButton = { TextButton(onClick = { confirmDelete = false }) { Text("Cancel") } },
        )
    }
}

@Composable
private fun RatingPicker(rating: Rating, onPick: (Rating) -> Unit) {
    SingleChoiceSegmentedButtonRow(Modifier.fillMaxWidth()) {
        Rating.entries.forEachIndexed { i, option ->
            SegmentedButton(
                selected = rating == option,
                onClick = { onPick(option) },
                shape = SegmentedButtonDefaults.itemShape(i, Rating.entries.size),
            ) { Text(option.label, maxLines = 1) }
        }
    }
}

/** Where an app or website goes: any category, back to automatic, or a new one. */
@Composable
private fun MoveDialog(
    item: CategoryItem,
    from: String,
    categories: List<Category>,
    order: List<String>,
    onPick: (String) -> Unit,
    onNew: () -> Unit,
    onDismiss: () -> Unit,
) {
    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text(item.name, maxLines = 2, overflow = TextOverflow.Ellipsis) },
        text = {
            Column(Modifier.verticalScroll(rememberScrollState())) {
                if (item.source == "assigned") {
                    Text(
                        "Automatic again",
                        color = MaterialTheme.colorScheme.primary,
                        modifier = Modifier.fillMaxWidth().clickable { onPick("") }.padding(vertical = 12.dp),
                    )
                    HorizontalDivider()
                }
                categories.filter { it.name != from }.forEach { category ->
                    Row(
                        Modifier.fillMaxWidth().clickable { onPick(category.name) }.padding(vertical = 10.dp),
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.spacedBy(10.dp),
                    ) {
                        Box(Modifier.size(10.dp).clip(CircleShape).background(categoryColor(order, category.name)))
                        Text(category.name, modifier = Modifier.weight(1f))
                        RatingChip(category.rating)
                    }
                }
            }
        },
        confirmButton = { TextButton(onClick = onNew) { Text("New category…") } },
        dismissButton = { TextButton(onClick = onDismiss) { Text("Cancel") } },
    )
}

@Composable
private fun NewCategoryDialog(item: CategoryItem?, onCreate: (String, Rating) -> Unit, onDismiss: () -> Unit) {
    var name by remember { mutableStateOf("") }
    var rating by remember { mutableStateOf(Rating.Neutral) }
    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text("New category") },
        text = {
            Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                if (item != null) Text("With ${item.name} in it.", style = MaterialTheme.typography.bodyMedium)
                OutlinedTextField(
                    name, { name = it },
                    label = { Text("Name") },
                    placeholder = { Text("Work > Studying") },
                    singleLine = true,
                    modifier = Modifier.fillMaxWidth(),
                )
                RatingPicker(rating) { rating = it }
            }
        },
        confirmButton = {
            TextButton(enabled = name.isNotBlank(), onClick = { onCreate(name.trim(), rating) }) { Text("Add") }
        },
        dismissButton = { TextButton(onClick = onDismiss) { Text("Cancel") } },
    )
}

/** An advanced rule: its patterns, case, devices, and what it would match. */
@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun RulePage(
    server: Server,
    rule: Rule,
    devices: List<String>,
    onSave: (Rule) -> Unit,
    onDelete: () -> Unit,
) {
    val scope = rememberCoroutineScope()
    var patterns by rememberSaveable { mutableStateOf(rule.patterns.joinToString("\n")) }
    var ignoreCase by rememberSaveable { mutableStateOf(rule.ignoreCase) }
    var only by remember { mutableStateOf(rule.devices.toSet()) }
    var preview by remember { mutableStateOf<Preview?>(null) }
    var problem by remember { mutableStateOf<String?>(null) }
    val entered = rule.copy(
        patterns = patterns.lines().map { it.trim() }.filter { it.isNotEmpty() },
        ignoreCase = ignoreCase,
        devices = only.toList(),
    )
    // what a preview showed is about what was entered then
    LaunchedEffect(patterns, ignoreCase, only) {
        preview = null
        problem = null
    }

    Column(
        Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(16.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        Text("Puts into ${rule.category}", style = MaterialTheme.typography.titleMedium)
        OutlinedTextField(
            patterns, { patterns = it },
            label = { Text("Patterns, one per line") },
            supportingText = {
                Text("Each is matched against the app (or website) and the window title. Plain words work, they are regular expressions.")
            },
            textStyle = MaterialTheme.typography.bodyMedium.copy(fontFamily = FontFamily.Monospace),
            minLines = 4,
            modifier = Modifier.fillMaxWidth(),
        )
        Row(verticalAlignment = Alignment.CenterVertically) {
            Checkbox(ignoreCase, { ignoreCase = it })
            Text("Ignore case")
        }
        if (devices.isNotEmpty()) {
            Text("Only on these devices (none: all)", style = MaterialTheme.typography.labelLarge)
            FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                devices.forEach { device ->
                    FilterChip(
                        selected = device in only,
                        onClick = { only = if (device in only) only - device else only + device },
                        label = { Text(device) },
                    )
                }
            }
        }
        problem?.let { Text(it, color = MaterialTheme.colorScheme.error) }
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            Button(enabled = entered.patterns.isNotEmpty(), onClick = { onSave(entered) }) { Text("Save") }
            OutlinedButton(enabled = entered.patterns.isNotEmpty(), onClick = {
                scope.launch {
                    withContext(Dispatchers.IO) { runCatching { CategoriesApi.preview(server, entered) } }
                        .onSuccess { preview = it }
                        .onFailure { problem = Sync.describe(it) }
                }
            }) { Text("Preview") }
            if (rule.id != 0) {
                TextButton(
                    onClick = onDelete,
                    colors = ButtonDefaults.textButtonColors(contentColor = MaterialTheme.colorScheme.error),
                ) { Text("Delete") }
            }
        }
        preview?.let { p ->
            Text(
                "Matches ${formatDuration(p.screenMs)} in the last 30 days",
                style = MaterialTheme.typography.titleSmall,
            )
            (p.apps.map { it.name to it.ms } + p.titles.take(10).map { it.name to it.ms }).forEach { (name, ms) ->
                Row {
                    Text(name, maxLines = 1, overflow = TextOverflow.Ellipsis, modifier = Modifier.weight(1f))
                    Text(formatDuration(ms), modifier = Modifier.padding(start = 12.dp))
                }
            }
        }
    }
}
