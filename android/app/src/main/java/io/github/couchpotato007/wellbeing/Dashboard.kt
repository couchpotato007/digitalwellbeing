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
import androidx.compose.runtime.MutableState
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
val lightColors = listOf(
    0xFF2A78D6, 0xFFEB6834, 0xFF1BAF7A, 0xFFEDA100, 0xFFE87BA4, 0xFF008300, 0xFF6250D6, 0xFFE34948,
).map { Color(it) }
val darkColors = listOf(
    0xFF3987E5, 0xFFD95926, 0xFF199E70, 0xFFC98500, 0xFFD55181, 0xFF008300, 0xFF9085E9, 0xFFE66767,
).map { Color(it) }

@Composable
fun categoryColor(order: List<String>, category: String): Color {
    val dark = isSystemInDarkTheme()
    val slot = colorSlot(order, category)
    return when {
        slot != null -> (if (dark) darkColors else lightColors)[slot]
        dark -> Color(0xFF6B6A64)
        else -> Color(0xFFA9A79F)
    }
}

/**
 * What the dashboard and the timeline show: the picked day, range and device,
 * and the report the server sent for them.
 */
class DashboardState(date: MutableState<String>, days: MutableState<Int>, device: MutableState<String>) {
    /** "" is today */
    var date by date
    var days by days
    /** "" is all devices */
    var device by device
    var report by mutableStateOf<Report?>(null)
    /** Null while loading, on errors and from servers without them. */
    var insights by mutableStateOf<Insights?>(null)
    var timeline by mutableStateOf<Timeline?>(null)
    var error by mutableStateOf<String?>(null)
    var loading by mutableStateOf(true)
    var retry by mutableIntStateOf(0)

    fun openDay(day: String) {
        date = day
        days = 1
    }
}

/** Loads the report again whenever the selection or [refresh] changes. */
@Composable
fun rememberDashboard(server: Server, refresh: Int): DashboardState {
    val date = rememberSaveable { mutableStateOf("") }
    val days = rememberSaveable { mutableStateOf(1) }
    val device = rememberSaveable { mutableStateOf("") }
    val state = remember { DashboardState(date, days, device) }
    LaunchedEffect(server, state.date, state.days, state.device, refresh, state.retry) {
        state.loading = true
        withContext(Dispatchers.IO) {
            runCatching {
                val report = Stats.load(server, state.date, state.days, state.device)
                // the dashboard works without these
                val insights = runCatching { Stats.insights(server, state.date, state.days, state.device) }.getOrNull()
                val timeline = runCatching { Stats.timeline(server, state.date, state.days, state.device) }.getOrNull()
                Triple(report, insights, timeline)
            }
        }
            .onSuccess { (report, insights, timeline) ->
                state.report = report
                state.insights = insights
                state.timeline = timeline
                state.error = null
            }
            .onFailure { state.error = it.message ?: it.toString() }
        state.loading = false
    }
    return state
}

/**
 * Screen time of all devices from the server: what happened first (totals,
 * over time, habits), then the details. Categories come last, they are only
 * as good as their rules.
 */
@Composable
fun Dashboard(state: DashboardState, onOpenTimeline: () -> Unit) {
    val current = state.report
    Controls(state)

    state.error?.let {
        Card {
            Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                Text("Could not load the dashboard: $it")
                OutlinedButton(onClick = { state.retry++ }) { Text("Retry") }
            }
        }
    }
    if (current == null) return
    val insights = state.insights
    val timeline = state.timeline
    val appColors = timeline?.let { seriesColors(it.series) }.orEmpty()

    SummaryCard(current, insights)
    if (timeline != null) TimelinePreviewCard(timeline, onOpenTimeline)
    if (current.days > 1) {
        ChartCard(
            "Per day · line: 7-day average",
            current.timeline,
            current.today,
            onOpenDay = state::openDay,
            marks = insights?.trend.orEmpty(),
        )
    }
    UsageList("Apps", current.apps, color = { appColors[it.name] ?: MaterialTheme.colorScheme.primary })
    if (insights != null) {
        ComparisonCard(insights, appColors)
        PhoneCard(current, insights)
        FocusCard(current, insights)
        WeekCard(insights.weekHours)
    }
    UsageList("Window titles", current.titles)
    UsageList("Browser domains", current.domains)
    if (current.device.isEmpty()) UsageList("Devices · last active", current.devices)
    val categoryTotal = current.categories.sumOf { it.ms }.coerceAtLeast(1)
    UsageList("Categories", current.categories, detail = { "${it.ms * 100 / categoryTotal}%" }) {
        categoryColor(current.categoryOrder, it.name)
    }
}

/** Day, week or 30 days, the date, and with [showDevices] the device. */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun Controls(state: DashboardState, showDevices: Boolean = true) {
    val report = state.report
    val days = state.days
    val device = state.device
    val loading = state.loading
    val onDays = { value: Int -> state.days = value }
    val onDate = { value: String -> state.date = value }
    val onDevice = { value: String -> state.device = value }
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

    if (!showDevices) return
    Row(
        Modifier.horizontalScroll(rememberScrollState()),
        horizontalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        FilterChip(selected = device.isEmpty(), onClick = { onDevice("") }, label = { Text("All devices") })
        report.deviceNames.forEach { name ->
            val os = report.deviceOs[name]
            FilterChip(
                selected = device == name,
                onClick = { onDevice(name) },
                label = { Text(if (os == null) name else "$name · ${osName(os)}") },
            )
        }
    }
}

private val dateFormat = DateTimeFormatter.ofLocalizedDate(FormatStyle.MEDIUM)

private fun formatDate(date: String) = LocalDate.parse(date).format(dateFormat)

/** "Mon, 26 Oct 2026" or "20 Oct 2026 – 26 Oct 2026" */
fun period(report: Report) =
    if (report.days == 1) {
        val date = LocalDate.parse(report.date)
        date.dayOfWeek.getDisplayName(java.time.format.TextStyle.SHORT, java.util.Locale.getDefault()) +
            ", " + date.format(dateFormat)
    } else {
        formatDate(report.firstDate) + " – " + formatDate(report.date)
    }

@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun SummaryCard(report: Report, insights: Insights?) {
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
                when (val os = report.deviceOs[report.device]) {
                    null -> report.device.ifEmpty { "All devices" }
                    else -> "${report.device} · $os"
                },
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
            insights?.total?.takeIf { it.periods >= 3 }?.let { total ->
                Text(
                    "Usually ${formatDuration(total.usualMs)}" + (if (insights.untilNow) " by this time" else "") +
                        " · " + verdict(total.score),
                    style = MaterialTheme.typography.bodyMedium,
                    color = verdictColor(total.score),
                )
            }
            if (insights != null) RatingBar(insights)
            Spacer(Modifier.height(8.dp))
            Tiles(tiles)
        }
    }
}

/** Productive, neutral and distracting time as one bar, by the ratings of their categories. */
@Composable
private fun RatingBar(insights: Insights) {
    val parts = listOf(
        Triple(Rating.Productive, insights.productiveMs, ratingColor(Rating.Productive)),
        Triple(Rating.Neutral, insights.neutralMs, ratingColor(Rating.Neutral)),
        Triple(Rating.Distracting, insights.distractingMs, ratingColor(Rating.Distracting)),
    )
    if (parts.sumOf { it.second } == 0L) return
    Column(Modifier.padding(top = 8.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
        Row(Modifier.fillMaxWidth().height(10.dp).clip(RoundedCornerShape(5.dp))) {
            parts.filter { it.second > 0 }.forEach { (_, ms, color) ->
                Box(Modifier.weight(ms.toFloat()).height(10.dp).background(color))
            }
        }
        Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
            parts.forEach { (rating, ms, color) ->
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Box(Modifier.size(8.dp).clip(RoundedCornerShape(2.dp)).background(color))
                    Text(
                        " ${rating.label} ${formatDuration(ms)}",
                        style = MaterialTheme.typography.labelSmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
            }
        }
    }
}

/** Label, value and note in up to 3 columns. */
@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun Tiles(tiles: List<Triple<String, String, String>>) {
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

/** A robust z-score in words, like the web dashboard. */
private fun verdict(score: Double) = when {
    score >= 3 -> "far more than usual"
    score >= 2 -> "more than usual"
    score <= -3 -> "far less than usual"
    score <= -2 -> "less than usual"
    else -> "within the usual range"
}

@Composable
private fun verdictColor(score: Double) = when {
    score >= 2 -> MaterialTheme.colorScheme.error
    score <= -2 -> Color(0xFF1B9A6A)
    else -> MaterialTheme.colorScheme.onSurfaceVariant
}

/** Apps against their usual time, the most unusual first. */
@Composable
private fun ComparisonCard(insights: Insights, appColors: Map<String, Color>) {
    if (insights.total.periods < 3 || insights.apps.isEmpty()) return
    val items = insights.apps.take(6)
    val max = items.maxOf { maxOf(it.ms, it.usualMs) }.coerceAtLeast(1)
    val track = MaterialTheme.colorScheme.surfaceVariant
    val mark = MaterialTheme.colorScheme.onSurface
    val primary = MaterialTheme.colorScheme.primary
    Card {
        Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
            Text(
                "Apps against what is usual" + if (insights.untilNow) " by this time" else "",
                style = MaterialTheme.typography.labelLarge,
            )
            items.forEach { c ->
                val color = appColors[c.name] ?: primary
                Column(verticalArrangement = Arrangement.spacedBy(2.dp)) {
                    Row(Modifier.fillMaxWidth()) {
                        Text(c.name, maxLines = 1, overflow = TextOverflow.Ellipsis, modifier = Modifier.weight(1f))
                        Text(formatDuration(c.ms), modifier = Modifier.padding(start = 12.dp))
                    }
                    Text(
                        "usually ${formatDuration(c.usualMs)} · ${verdict(c.score)}",
                        style = MaterialTheme.typography.bodySmall,
                        color = verdictColor(c.score),
                    )
                    Canvas(Modifier.fillMaxWidth().height(8.dp)) {
                        val y = size.height / 2
                        val h = 6.dp.toPx()
                        drawRoundRect(track, Offset(0f, y - h / 2), Size(size.width, h), CornerRadius(h / 2))
                        drawRoundRect(color, Offset(0f, y - h / 2), Size(size.width * c.ms / max, h), CornerRadius(h / 2))
                        val x = size.width * c.usualMs / max
                        drawRect(mark, Offset(x - 1.dp.toPx(), 0f), Size(2.dp.toPx(), size.height))
                    }
                }
            }
        }
    }
}

private fun perDay(count: Int, days: Int) =
    if (days == 1) count.toString() else "%.1f a day".format(count.toDouble() / days)

private fun share(part: Int, whole: Int) = if (whole == 0) "–" else "${part * 100 / whole}%"

/** Pickups, notifications and media, from phones. */
@Composable
private fun PhoneCard(report: Report, insights: Insights) {
    if (insights.pickups + insights.notifications + insights.screenOns == 0) return
    val days = report.days
    Card {
        Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
            Text("Phone habits", style = MaterialTheme.typography.labelLarge)
            Tiles(
                listOf(
                    Triple("Pickups", perDay(insights.pickups, days), if (days > 1) "${insights.pickups} in total" else ""),
                    Triple(if (days > 1) "First pickup, median" else "First pickup", insights.firstPickup.ifEmpty { "–" }, ""),
                    Triple("Notifications", perDay(insights.notifications, days), ""),
                    Triple("After a notification", share(insights.notificationPickups, insights.pickups), "of pickups, within a minute"),
                    Triple(
                        "Screen on < 1 min",
                        share(insights.shortScreenOns, insights.screenOns),
                        "median ${formatDuration(insights.medianScreenOnMs)}",
                    ),
                    Triple("Media playing", if (insights.audioMs == 0L) "–" else formatDuration(insights.audioMs), ""),
                )
            )
            Text("Pickups by hour", style = MaterialTheme.typography.labelMedium)
            CountBars(insights.pickupHours)
            CountList("Opened first after unlocking", insights.pickupApps)
            CountList("Notifications", insights.notificationApps)
        }
    }
    UsageList("Media", insights.audioApps)
}

/** Long stretches in one category, switching, and the phone next to a computer. */
@Composable
private fun FocusCard(report: Report, insights: Insights) {
    if (report.totalMs == 0L) return
    val hours = (report.totalMs / 3_600_000).coerceAtLeast(1)
    Card {
        Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
            Text("Focus", style = MaterialTheme.typography.labelLarge)
            Tiles(
                buildList {
                    add(
                        Triple(
                            "Productive stretches 25+ min",
                            insights.longStretches.toString(),
                            "${formatDuration(insights.longStretchMs)} · " +
                                "${insights.longStretchMs * 100 / report.totalMs}%",
                        )
                    )
                    val longest = insights.longestStretch
                    add(
                        Triple(
                            "Longest stretch",
                            if (longest.ms == 0L) "–" else formatDuration(longest.ms),
                            "${longest.name} ${longest.detail}".trim(),
                        )
                    )
                    add(Triple("App switches", "${insights.appSwitches / hours} an hour", "${insights.appSwitches} in total"))
                    add(Triple("Typical session", formatDuration(insights.medianSessionMs), "median"))
                    if (report.device.isEmpty() && insights.phoneDuringComputerMs > 0) {
                        add(Triple("Phone at a computer", formatDuration(insights.phoneDuringComputerMs), ""))
                        add(Triple("Pickups at a computer", insights.pickupsDuringComputer.toString(), ""))
                    }
                }
            )
        }
    }
    UsageList("Long stretches by category", insights.longStretchCategories, detail = { "" }) {
        categoryColor(report.categoryOrder, it.name)
    }
}

/** When screen time usually happens: weekdays by hours of the last 4 weeks. */
@Composable
private fun WeekCard(week: List<List<Long>>) {
    val max = week.flatten().maxOrNull() ?: 0L
    if (max == 0L || week.size != 7) return
    val bar = MaterialTheme.colorScheme.primary
    val empty = MaterialTheme.colorScheme.surfaceVariant
    // Monday first
    val rows = (week.drop(1) + week.take(1)).zip(listOf("Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"))
    Card {
        Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(3.dp)) {
            Text("Usual week · last 4 weeks", style = MaterialTheme.typography.labelLarge)
            rows.forEach { (hours, day) ->
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Text(day, style = MaterialTheme.typography.labelSmall, modifier = Modifier.width(36.dp))
                    Canvas(Modifier.weight(1f).height(12.dp)) {
                        val cell = size.width / 24
                        hours.forEachIndexed { h, ms ->
                            val color = if (ms == 0L) empty else bar.copy(alpha = 0.12f + 0.88f * ms / max)
                            drawRoundRect(
                                color,
                                Offset(h * cell + 1, 0f),
                                Size(cell - 2, size.height),
                                CornerRadius(2.dp.toPx()),
                            )
                        }
                    }
                }
            }
            Row {
                Spacer(Modifier.width(36.dp))
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
private fun CountBars(values: List<Int>) {
    val bar = MaterialTheme.colorScheme.primary
    val max = (values.maxOrNull() ?: 0).coerceAtLeast(1)
    Canvas(Modifier.fillMaxWidth().height(60.dp)) {
        val slot = size.width / values.size
        val width = (slot - 2.dp.toPx()).coerceAtLeast(1f)
        values.forEachIndexed { i, n ->
            val height = (size.height * n / max).coerceAtLeast(if (n > 0) 2.dp.toPx() else 0f)
            drawRoundRect(
                bar,
                Offset(i * slot + (slot - width) / 2, size.height - height),
                Size(width, height),
                CornerRadius(minOf(3.dp.toPx(), width / 2)),
            )
        }
    }
    Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
        listOf("0", "6", "12", "18", "24").forEach {
            Text(it, style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
    }
}

@Composable
private fun CountList(title: String, items: List<CountItem>) {
    if (items.isEmpty()) return
    val max = items.maxOf { it.count }.coerceAtLeast(1)
    val track = MaterialTheme.colorScheme.surfaceVariant
    val bar = MaterialTheme.colorScheme.primary
    Text(title, style = MaterialTheme.typography.labelMedium, modifier = Modifier.padding(top = 4.dp))
    items.forEach { item ->
        Column(verticalArrangement = Arrangement.spacedBy(2.dp)) {
            Row(Modifier.fillMaxWidth()) {
                Text(item.name, maxLines = 1, overflow = TextOverflow.Ellipsis, modifier = Modifier.weight(1f))
                Text("${item.count}×", modifier = Modifier.padding(start = 12.dp))
            }
            Box(Modifier.fillMaxWidth().height(4.dp).clip(RoundedCornerShape(2.dp)).background(track)) {
                Box(
                    Modifier
                        .fillMaxWidth(item.count.toFloat() / max)
                        .height(4.dp)
                        .clip(RoundedCornerShape(2.dp))
                        .background(bar)
                )
            }
        }
    }
}

/**
 * Bars per hour ("07") or day ("2026-10-26"). Tapping a bar shows its time,
 * a day then can be opened with [onOpenDay].
 */
@Composable
private fun ChartCard(
    title: String,
    buckets: List<UsageItem>,
    today: String,
    onOpenDay: ((String) -> Unit)?,
    marks: List<Long> = emptyList(),
) {
    val markColor = MaterialTheme.colorScheme.onSurface
    val bar = MaterialTheme.colorScheme.primary
    val todayBar = MaterialTheme.colorScheme.tertiary
    val muted = MaterialTheme.colorScheme.onSurfaceVariant
    var selected by remember(buckets) { mutableStateOf<Int?>(null) }
    val max = maxOf(buckets.maxOfOrNull { it.ms } ?: 0L, marks.maxOrNull() ?: 0L).coerceAtLeast(1)
    // a line per bucket, if there is one for each
    val lines = marks.takeIf { it.size == buckets.size }
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
                        isDay(pick) -> "${pick.detail} ${formatDate(pick.name)}: ${formatDuration(pick.ms)}" +
                            (lines?.getOrNull(selected!!)?.let { ", 7-day average ${formatDuration(it)}" } ?: "")
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
                lines?.let {
                    val points = it.mapIndexed { i, ms -> Offset(i * slot + slot / 2, size.height * (1 - ms.toFloat() / max)) }
                    points.zipWithNext { a, b -> drawLine(markColor.copy(alpha = 0.7f), a, b, 2.dp.toPx()) }
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
