package io.github.couchpotato007.wellbeing

import android.app.DatePickerDialog
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Card
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FilterChip
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
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
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import java.time.LocalDate
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.time.format.FormatStyle

/** The category colors of the web dashboard, in the order of [colorSlot]. */
private val lightColors = listOf(
    0xFF2A78D6, 0xFFEB6834, 0xFF1BAF7A, 0xFFEDA100, 0xFFE87BA4, 0xFF008300, 0xFF6250D6, 0xFFE34948,
).map { Color(it) }
private val darkColors = listOf(
    0xFF3987E5, 0xFFD95926, 0xFF199E70, 0xFFC98500, 0xFFD55181, 0xFF008300, 0xFF9085E9, 0xFFE66767,
).map { Color(it) }

@Composable
private fun categoryColor(order: List<String>, category: String): Color {
    val dark = isSystemInDarkTheme()
    val slot = colorSlot(order, category)
    return when {
        slot != null -> (if (dark) darkColors else lightColors)[slot]
        dark -> Color(0xFF6B6A64)
        else -> Color(0xFFA9A79F)
    }
}

/** Screen time of all devices from the server, with a device, day and range to pick. */
@Composable
fun Dashboard(server: Server, refresh: Int) {
    // "" is today
    var date by rememberSaveable { mutableStateOf("") }
    var days by rememberSaveable { mutableIntStateOf(1) }
    // "" is all devices
    var device by rememberSaveable { mutableStateOf("") }
    var retry by remember { mutableIntStateOf(0) }
    var report by remember { mutableStateOf<Report?>(null) }
    var error by remember { mutableStateOf<String?>(null) }
    var loading by remember { mutableStateOf(true) }

    LaunchedEffect(server, date, days, device, refresh, retry) {
        loading = true
        withContext(Dispatchers.IO) { runCatching { Stats.load(server, date, days, device) } }
            .onSuccess {
                report = it
                error = null
            }
            .onFailure { error = it.message ?: it.toString() }
        loading = false
    }

    val current = report
    Controls(
        report = current,
        days = days,
        device = device,
        loading = loading,
        onDays = { days = it },
        onDate = { date = it },
        onDevice = { device = it },
    )

    error?.let {
        Card {
            Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                Text("Could not load the dashboard: $it")
                OutlinedButton(onClick = { retry++ }) { Text("Retry") }
            }
        }
    }
    if (current == null) return

    val openDay = { day: String ->
        date = day
        days = 1
    }
    SummaryCard(current)
    ChartCard(
        if (current.days == 1) "Per hour" else "Per day",
        current.timeline,
        current.today,
        onOpenDay = openDay,
    )
    if (current.strips.isNotEmpty()) ActivityCard(current, onOpenDay = openDay)
    if (current.days > 1) {
        ChartCard(
            "By hour of day · average per day",
            current.hours.map { it.copy(ms = it.ms / current.days) },
            current.today,
            onOpenDay = null,
        )
    }
    val categoryTotal = current.categories.sumOf { it.ms }.coerceAtLeast(1)
    UsageList("Categories", current.categories, detail = { "${it.ms * 100 / categoryTotal}%" }) {
        categoryColor(current.categoryOrder, it.name)
    }
    UsageList("Apps", current.apps)
    UsageList("Window titles", current.titles)
    UsageList("Browser domains", current.domains)
    if (current.device.isEmpty()) UsageList("Devices · last active", current.devices)
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun Controls(
    report: Report?,
    days: Int,
    device: String,
    loading: Boolean,
    onDays: (Int) -> Unit,
    onDate: (String) -> Unit,
    onDevice: (String) -> Unit,
) {
    val context = LocalContext.current
    val ranges = listOf(1 to "Day", 7 to "Week", 30 to "30 days")
    SingleChoiceSegmentedButtonRow(Modifier.fillMaxWidth()) {
        ranges.forEachIndexed { i, (value, label) ->
            SegmentedButton(
                selected = days == value,
                onClick = { onDays(value) },
                shape = SegmentedButtonDefaults.itemShape(i, ranges.size),
            ) { Text(label) }
        }
    }
    if (report == null) return

    Row(verticalAlignment = Alignment.CenterVertically) {
        TextButton(onClick = { onDate(report.previousDate) }) { Text("‹", style = MaterialTheme.typography.titleLarge) }
        TextButton(
            modifier = Modifier.weight(1f),
            onClick = {
                val shown = LocalDate.parse(report.date)
                DatePickerDialog(
                    context,
                    { _, year, month, day -> onDate(LocalDate.of(year, month + 1, day).toString()) },
                    shown.year, shown.monthValue - 1, shown.dayOfMonth,
                ).apply {
                    datePicker.maxDate = LocalDate.parse(report.today)
                        .atStartOfDay(ZoneId.systemDefault()).toInstant().toEpochMilli()
                }.show()
            },
        ) { Text(period(report), textAlign = TextAlign.Center) }
        if (loading) CircularProgressIndicator(Modifier.size(20.dp), strokeWidth = 2.dp)
        TextButton(enabled = report.date < report.today, onClick = { onDate(report.nextDate) }) {
            Text("›", style = MaterialTheme.typography.titleLarge)
        }
        TextButton(enabled = report.date != report.today, onClick = { onDate("") }) { Text("Today") }
    }

    Row(
        Modifier.horizontalScroll(rememberScrollState()),
        horizontalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        FilterChip(selected = device.isEmpty(), onClick = { onDevice("") }, label = { Text("All devices") })
        report.deviceNames.forEach { name ->
            FilterChip(selected = device == name, onClick = { onDevice(name) }, label = { Text(name) })
        }
    }
}

private val dateFormat = DateTimeFormatter.ofLocalizedDate(FormatStyle.MEDIUM)

private fun formatDate(date: String) = LocalDate.parse(date).format(dateFormat)

/** "Mon, 26 Oct 2026" or "20 Oct 2026 – 26 Oct 2026" */
private fun period(report: Report) =
    if (report.days == 1) {
        val date = LocalDate.parse(report.date)
        date.dayOfWeek.getDisplayName(java.time.format.TextStyle.SHORT, java.util.Locale.getDefault()) +
            ", " + date.format(dateFormat)
    } else {
        formatDate(report.firstDate) + " – " + formatDate(report.date)
    }

@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun SummaryCard(report: Report) {
    val previous = when (report.days) {
        1 -> "the day before"
        7 -> "the week before"
        else -> "the ${report.days} days before"
    }
    val change = if (report.previousMs == 0L) "–" else {
        val percent = (report.totalMs - report.previousMs) * 100 / report.previousMs
        when {
            percent > 0 -> "↑ $percent%"
            percent < 0 -> "↓ ${-percent}%"
            else -> "±0%"
        }
    }
    val tiles = buildList {
        if (report.days > 1) add(Triple("Daily average", formatDuration(report.totalMs / report.days), ""))
        add(Triple("vs. $previous", change, formatDuration(report.previousMs)))
        add(Triple("Sessions", report.sessions.toString(), "breaks of 5+ min"))
        add(Triple("Longest session", formatDuration(report.longestSessionMs), ""))
        if (report.days == 1) {
            add(Triple("First active", report.firstActive.ifEmpty { "–" }, ""))
            add(Triple("Last active", report.lastActive.ifEmpty { "–" }, ""))
        } else {
            val busiest = report.timeline.maxByOrNull { it.ms }?.takeIf { it.ms > 0 }
            add(
                Triple(
                    "Busiest day",
                    busiest?.let { "${it.detail} ${it.name.takeLast(5)}" } ?: "–",
                    busiest?.let { formatDuration(it.ms) } ?: "",
                )
            )
        }
    }

    Card {
        Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(4.dp)) {
            Text(formatDuration(report.totalMs), style = MaterialTheme.typography.displaySmall)
            Text(
                report.device.ifEmpty { "All devices" },
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
            Spacer(Modifier.height(8.dp))
            FlowRow(
                horizontalArrangement = Arrangement.spacedBy(16.dp),
                verticalArrangement = Arrangement.spacedBy(12.dp),
                maxItemsInEachRow = 3,
            ) {
                tiles.forEach { (label, value, note) ->
                    Column(Modifier.weight(1f).width(96.dp)) {
                        Text(label, style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                        Text(value, style = MaterialTheme.typography.titleMedium)
                        if (note.isNotEmpty()) {
                            Text(note, style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                        }
                    }
                }
            }
        }
    }
}

/**
 * Bars per hour ("07") or day ("2026-10-26"). Tapping a bar shows its time,
 * a day then can be opened with [onOpenDay].
 */
@Composable
private fun ChartCard(title: String, buckets: List<UsageItem>, today: String, onOpenDay: ((String) -> Unit)?) {
    val bar = MaterialTheme.colorScheme.primary
    val todayBar = MaterialTheme.colorScheme.tertiary
    val muted = MaterialTheme.colorScheme.onSurfaceVariant
    var selected by remember(buckets) { mutableStateOf<Int?>(null) }
    val max = (buckets.maxOfOrNull { it.ms } ?: 0L).coerceAtLeast(1)
    val isDay = { item: UsageItem -> item.name.length == 10 }
    // at most about 8 labels
    val every = ((buckets.size + 7) / 8).coerceAtLeast(1)

    Card {
        Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(4.dp)) {
            Text(title, style = MaterialTheme.typography.labelLarge)
            val pick = selected?.let { buckets.getOrNull(it) }
            Row(verticalAlignment = Alignment.CenterVertically, modifier = Modifier.height(40.dp)) {
                Text(
                    when {
                        pick == null -> "max ${formatDuration(max)} · tap a bar"
                        isDay(pick) -> "${pick.detail} ${formatDate(pick.name)}: ${formatDuration(pick.ms)}"
                        else -> "${pick.name}:00–${pick.name}:59: ${formatDuration(pick.ms)}"
                    },
                    style = MaterialTheme.typography.bodySmall,
                    color = muted,
                    modifier = Modifier.weight(1f),
                )
                if (pick != null && onOpenDay != null && isDay(pick)) {
                    TextButton(onClick = { onOpenDay(pick.name) }) { Text("Open day") }
                }
            }
            Canvas(
                Modifier
                    .fillMaxWidth()
                    .height(140.dp)
                    .pointerInput(buckets) {
                        detectTapGestures { offset ->
                            val i = (offset.x / (size.width.toFloat() / buckets.size)).toInt()
                            selected = if (selected == i) null else i.coerceIn(0, buckets.lastIndex)
                        }
                    }
            ) {
                val slot = size.width / buckets.size
                val width = (slot - 2.dp.toPx()).coerceAtLeast(1f)
                buckets.forEachIndexed { i, item ->
                    val height = (size.height * item.ms / max).coerceAtLeast(2.dp.toPx())
                    val color = when {
                        isDay(item) && item.name == today -> todayBar
                        else -> bar
                    }
                    drawRoundRect(
                        color = if (selected == null || selected == i) color else color.copy(alpha = 0.4f),
                        topLeft = Offset(i * slot + (slot - width) / 2, size.height - height),
                        size = Size(width, height),
                        cornerRadius = CornerRadius(minOf(4.dp.toPx(), width / 2)),
                    )
                }
            }
            Row(Modifier.fillMaxWidth()) {
                buckets.forEachIndexed { i, item ->
                    Text(
                        when {
                            i % every != 0 -> ""
                            !isDay(item) -> item.name
                            buckets.size <= 7 -> item.detail
                            else -> item.name.takeLast(2)
                        },
                        style = MaterialTheme.typography.labelSmall,
                        color = muted,
                        maxLines = 1,
                        softWrap = false,
                        overflow = TextOverflow.Visible,
                        modifier = Modifier.weight(1f),
                    )
                }
            }
        }
    }
}

/** When which category was used, per device for a day or per day for longer. */
@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun ActivityCard(report: Report, onOpenDay: (String) -> Unit) {
    val order = report.categoryOrder
    val shown = report.strips.flatMap { s -> s.segments.map { topLevel(it.category) } }.distinct()
    val legend = order.filter { it in shown } + shown.filter { it !in order }
    val track = MaterialTheme.colorScheme.surfaceVariant
    // resolved here, Canvas can't call composables
    val colors = (legend + report.strips.flatMap { s -> s.segments.map { it.category } }).distinct()
        .associateWith { categoryColor(order, it) }

    Card {
        Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
            Text(
                if (report.days == 1) "Activity per device" else "Activity per day",
                style = MaterialTheme.typography.labelLarge,
            )
            FlowRow(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                legend.forEach { name ->
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Box(Modifier.size(10.dp).clip(RoundedCornerShape(3.dp)).background(colors.getValue(name)))
                        Text(" $name", style = MaterialTheme.typography.labelSmall)
                    }
                }
            }
            report.strips.forEach { strip ->
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Text(
                        strip.label,
                        style = MaterialTheme.typography.labelMedium,
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis,
                        modifier = Modifier
                            .width(72.dp)
                            .let { if (strip.date.isEmpty()) it else it.clickable { onOpenDay(strip.date) } },
                    )
                    Canvas(
                        Modifier
                            .weight(1f)
                            .height(16.dp)
                            .clip(RoundedCornerShape(4.dp))
                            .background(track)
                    ) {
                        val length = (strip.endMs - strip.startMs).coerceAtLeast(1).toFloat()
                        strip.segments.forEach { s ->
                            val x = size.width * (s.startMs - strip.startMs) / length
                            val w = (size.width * (s.endMs - s.startMs) / length).coerceAtLeast(1.dp.toPx())
                            drawRect(colors.getValue(s.category), Offset(x, 0f), Size(w, size.height))
                        }
                    }
                }
            }
            Row {
                Spacer(Modifier.width(72.dp))
                Row(Modifier.weight(1f), horizontalArrangement = Arrangement.SpaceBetween) {
                    listOf("0", "6", "12", "18", "24").forEach {
                        Text(it, style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                    }
                }
            }
        }
    }
}

@Composable
private fun UsageList(
    title: String,
    items: List<UsageItem>,
    detail: (UsageItem) -> String = { it.detail },
    color: @Composable (UsageItem) -> Color = { MaterialTheme.colorScheme.primary },
) {
    if (items.isEmpty()) return
    val max = items.maxOf { it.ms }.coerceAtLeast(1)
    val track = MaterialTheme.colorScheme.surfaceVariant
    Card {
        Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
            Text(title, style = MaterialTheme.typography.labelLarge)
            items.forEach { item ->
                Column(verticalArrangement = Arrangement.spacedBy(2.dp)) {
                    Row(Modifier.fillMaxWidth()) {
                        Text(item.name, maxLines = 1, overflow = TextOverflow.Ellipsis, modifier = Modifier.weight(1f))
                        Text(formatDuration(item.ms), modifier = Modifier.padding(start = 12.dp))
                    }
                    val text = detail(item)
                    if (text.isNotEmpty()) {
                        Text(
                            text,
                            style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                            maxLines = 1,
                            overflow = TextOverflow.Ellipsis,
                        )
                    }
                    Box(Modifier.fillMaxWidth().height(4.dp).clip(RoundedCornerShape(2.dp)).background(track)) {
                        Box(
                            Modifier
                                .fillMaxWidth(item.ms.toFloat() / max)
                                .height(4.dp)
                                .clip(RoundedCornerShape(2.dp))
                                .background(color(item))
                        )
                    }
                }
            }
        }
    }
}
