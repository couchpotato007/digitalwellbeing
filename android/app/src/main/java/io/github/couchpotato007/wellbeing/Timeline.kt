package io.github.couchpotato007.wellbeing

import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.animateContentSize
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.tween
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.gestures.detectHorizontalDragGestures
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Card
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.drawscope.DrawScope
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.text.drawText
import androidx.compose.ui.text.rememberTextMeasurer
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp

/** "Other" and apps beyond the palette. */
private val otherLight = Color(0xFFA9A79F)
private val otherDark = Color(0xFF6B6A64)

/** The color of each series, by rank, the same on all cards. */
@Composable
fun seriesColors(series: List<Series>): Map<String, Color> {
    val dark = isSystemInDarkTheme()
    val palette = if (dark) darkColors else lightColors
    return series.mapIndexed { i, s ->
        s.name to if (s.name == "Other" || i >= palette.size) (if (dark) otherDark else otherLight) else palette[i]
    }.toMap()
}

@Composable
private fun otherColor() = if (isSystemInDarkTheme()) otherDark else otherLight

/**
 * The timeline tab: screen time per app as stacked areas over the day (or
 * week, or month), drag over it to see a moment, and the sessions below.
 */
@Composable
fun TimelineScreen(state: DashboardState) {
    val report = state.report
    val timeline = state.timeline
    // the session shown on the chart, by its start
    var picked by rememberSaveable(report?.date, report?.days, report?.device) { mutableStateOf<Long?>(null) }

    Column(
        Modifier
            .fillMaxSize()
            .verticalScroll(rememberScrollState())
            .padding(16.dp),
        verticalArrangement = Arrangement.spacedBy(16.dp),
    ) {
        Text("Timeline", style = MaterialTheme.typography.headlineMedium)
        Controls(state)
        when {
            report == null -> Text(state.error ?: "Loading…")
            timeline == null -> Text(
                "The server is too old for the timeline, update it.",
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
            timeline.series.isEmpty() -> Text(
                "Nothing recorded in this time.",
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
            else -> {
                val colors = seriesColors(timeline.series)
                val session = timeline.sessions.find { it.startMs == picked }
                ChartCard(timeline, colors, session)
                if (timeline.sessions.isNotEmpty()) {
                    SessionsCard(timeline.sessions, colors, report.days > 1, picked) {
                        picked = if (picked == it.startMs) null else it.startMs
                    }
                } else {
                    Text(
                        "Sessions are listed for up to a week.",
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
            }
        }
    }
}

@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun ChartCard(timeline: Timeline, colors: Map<String, Color>, session: Session?) {
    var selected by remember(timeline) { mutableStateOf<Int?>(null) }
    val bucket = selected?.let { timeline.buckets.getOrNull(it) }
    val total = timeline.buckets.sumOf { it.ms }

    Card {
        Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
            Column(Modifier.height(48.dp)) {
                Text(
                    if (bucket == null) formatDuration(total) else formatDuration(bucket.ms),
                    style = MaterialTheme.typography.headlineSmall,
                )
                Text(
                    when {
                        bucket != null -> "${bucket.label} · ${bucketLength(timeline)}"
                        session != null -> "Session ${session.start}–${session.end}"
                        else -> "Drag over the chart to see a moment"
                    },
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
            AreaChart(
                timeline,
                colors,
                Modifier.fillMaxWidth().height(220.dp),
                selected = selected,
                onSelect = { selected = it },
                highlight = session?.let { it.startMs to it.endMs },
            )
            TimeAxis(timeline)
            FlowRow(
                horizontalArrangement = Arrangement.spacedBy(14.dp),
                verticalArrangement = Arrangement.spacedBy(6.dp),
                modifier = Modifier.padding(top = 4.dp),
            ) {
                timeline.series.forEach { s ->
                    val ms = if (selected == null) s.totalMs else s.values.getOrElse(selected!!) { 0 }
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Box(Modifier.size(10.dp).clip(CircleShape).background(colors.getValue(s.name)))
                        Text(
                            " ${s.name} ",
                            style = MaterialTheme.typography.labelMedium,
                            maxLines = 1,
                            overflow = TextOverflow.Ellipsis,
                        )
                        Text(
                            formatDuration(ms),
                            style = MaterialTheme.typography.labelMedium,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                    }
                }
            }
        }
    }
}

/** "15 min", "1 hour" or "1 day", what a bucket of the chart covers. */
private fun bucketLength(timeline: Timeline): String {
    val b = timeline.buckets.firstOrNull() ?: return ""
    return when (val minutes = (b.endMs - b.startMs) / 60_000) {
        in 0..59 -> "$minutes min"
        in 60..120 -> "1 hour"
        else -> "1 day"
    }
}

/** Labels under the chart: hours of a day, weekdays of a week, some dates of a month. */
@Composable
private fun TimeAxis(timeline: Timeline) {
    val buckets = timeline.buckets
    val labels = when {
        buckets.size == 96 -> listOf("0", "6", "12", "18", "24")
        buckets.size % 24 == 0 -> buckets.chunked(24).map { it.first().label.substringBefore(' ') }
        else -> buckets.filterIndexed { i, _ -> i % ((buckets.size + 4) / 5).coerceAtLeast(1) == 0 }.map { it.label }
    }
    Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
        labels.forEach {
            Text(it, style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
    }
}

/**
 * The series stacked as smooth areas, the most used at the bottom. With
 * [onSelect], tapping or dragging picks a bucket, which gets a line;
 * [highlight] (from, until) is shaded.
 */
@Composable
fun AreaChart(
    timeline: Timeline,
    colors: Map<String, Color>,
    modifier: Modifier,
    selected: Int? = null,
    onSelect: ((Int?) -> Unit)? = null,
    highlight: Pair<Long, Long>? = null,
    grid: Boolean = true,
) {
    val buckets = timeline.buckets
    val n = buckets.size
    val lineColor = MaterialTheme.colorScheme.onSurface
    val gridColor = MaterialTheme.colorScheme.outlineVariant
    val labelStyle = MaterialTheme.typography.labelSmall.copy(color = MaterialTheme.colorScheme.onSurfaceVariant)
    val measurer = rememberTextMeasurer()
    val fallback = otherColor()
    // grows in when the data changes
    val grow by animateFloatAsState(1f, tween(500), label = "grow")

    val stacks = remember(timeline) {
        var below = List(n) { 0L }
        timeline.series.map { s ->
            val top = below.zip(s.values) { a, b -> a + b }
            Triple(s.name, below, top).also { below = top }
        }
    }
    val max = niceMax(buckets.maxOfOrNull { it.ms } ?: 0L)

    val pick = { x: Float, width: Float -> (x / width * n).toInt().coerceIn(0, n - 1) }
    val input = if (onSelect == null) Modifier else Modifier
        .pointerInput(timeline) {
            detectTapGestures { offset ->
                val i = pick(offset.x, size.width.toFloat())
                onSelect(if (selected == i) null else i)
            }
        }
        .pointerInput(timeline) {
            detectHorizontalDragGestures(
                onDragStart = { onSelect(pick(it.x, size.width.toFloat())) },
            ) { change, _ -> onSelect(pick(change.position.x, size.width.toFloat())) }
        }

    Canvas(modifier.then(input)) {
        if (n == 0) return@Canvas
        val step = size.width / n
        val x = { i: Int -> (i + 0.5f) * step }
        val y = { ms: Long -> size.height - size.height * ms / max * grow }

        if (grid) {
            for (k in 1..3) {
                val ms = max * k / 3
                val gy = y(ms)
                drawLine(gridColor, Offset(0f, gy), Offset(size.width, gy), 1.dp.toPx())
                drawText(measurer, formatDuration(ms), Offset(4.dp.toPx(), gy + 2.dp.toPx()), labelStyle)
            }
        }
        highlight?.let { (from, until) ->
            val a = buckets.indexOfFirst { it.endMs > from }.coerceAtLeast(0)
            val b = buckets.indexOfLast { it.startMs < until }.coerceAtLeast(a)
            drawRect(lineColor.copy(alpha = 0.08f), Offset(a * step, 0f), Size((b - a + 1) * step, size.height))
        }

        stacks.forEach { (name, below, top) ->
            val color = colors[name] ?: fallback
            val area = Path().apply {
                smooth(this, top.mapIndexed { i, ms -> Offset(x(i), y(ms)) }, step, first = true)
                smooth(this, below.mapIndexed { i, ms -> Offset(x(i), y(ms)) }.reversed(), -step, first = false)
                close()
            }
            drawPath(
                area,
                Brush.verticalGradient(listOf(color.copy(alpha = 0.95f), color.copy(alpha = 0.6f))),
            )
            val edge = Path().apply { smooth(this, top.mapIndexed { i, ms -> Offset(x(i), y(ms)) }, step, first = true) }
            drawPath(edge, color, style = Stroke(1.5.dp.toPx()))
        }

        selected?.let { i ->
            drawLine(lineColor.copy(alpha = 0.7f), Offset(x(i), 0f), Offset(x(i), size.height), 1.5.dp.toPx())
            stacks.forEach { (name, below, top) ->
                if (top[i] > below[i]) drawCircle(colors[name] ?: fallback, 3.5.dp.toPx(), Offset(x(i), y(top[i])))
            }
        }
    }
}

/**
 * Adds a smooth line through [points] to [path]: flat to the edge half a
 * [step] before the first and after the last point, and between points a
 * curve that doesn't overshoot (both controls at the middle x), so an area
 * never dips below zero or above the next one.
 */
private fun DrawScope.smooth(path: Path, points: List<Offset>, step: Float, first: Boolean) {
    if (points.isEmpty()) return
    val start = Offset(points.first().x - step / 2, points.first().y)
    if (first) path.moveTo(start.x, start.y) else path.lineTo(start.x, start.y)
    path.lineTo(points.first().x, points.first().y)
    points.zipWithNext { a, b ->
        val mid = (a.x + b.x) / 2
        path.cubicTo(mid, a.y, mid, b.y, b.x, b.y)
    }
    path.lineTo(points.last().x + step / 2, points.last().y)
}

/** A round top for the axis: 15m, 30m, 1h, 2h, … above [ms]. */
private fun niceMax(ms: Long): Long {
    val steps = listOf(5L, 10, 15, 30, 60, 120, 180, 240, 360, 480, 720, 960, 1440).map { it * 60_000 }
    return steps.firstOrNull { it >= ms } ?: ms.coerceAtLeast(1)
}

/** The sessions, per day for several days. Tapping one shows its apps and marks it on the chart. */
@Composable
private fun SessionsCard(
    sessions: List<Session>,
    colors: Map<String, Color>,
    byDay: Boolean,
    picked: Long?,
    onPick: (Session) -> Unit,
) {
    Card {
        Column(Modifier.padding(vertical = 12.dp)) {
            Text(
                "Sessions · breaks of 5+ min",
                style = MaterialTheme.typography.labelLarge,
                modifier = Modifier.padding(horizontal = 16.dp, vertical = 4.dp),
            )
            sessions.groupBy { it.date }.entries.reversed().forEach { (date, ofDay) ->
                if (byDay) {
                    Text(
                        runCatching { java.time.LocalDate.parse(date).format(dayFormat) }.getOrDefault(date),
                        style = MaterialTheme.typography.labelMedium,
                        color = MaterialTheme.colorScheme.primary,
                        modifier = Modifier.padding(start = 16.dp, top = 12.dp, bottom = 2.dp),
                    )
                }
                ofDay.reversed().forEach { session ->
                    SessionRow(session, colors, session.startMs == picked) { onPick(session) }
                }
            }
        }
    }
}

private val dayFormat = java.time.format.DateTimeFormatter.ofPattern("EEEE, d MMMM")

@Composable
private fun SessionRow(session: Session, colors: Map<String, Color>, open: Boolean, onClick: () -> Unit) {
    val fallback = otherColor()
    val track = MaterialTheme.colorScheme.surfaceVariant
    Column(
        Modifier
            .fillMaxWidth()
            .clickable(onClick = onClick)
            .background(if (open) MaterialTheme.colorScheme.secondaryContainer.copy(alpha = 0.5f) else Color.Transparent)
            .padding(horizontal = 16.dp, vertical = 10.dp)
            .animateContentSize(),
        verticalArrangement = Arrangement.spacedBy(6.dp),
    ) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Text("${session.start}–${session.end}", style = MaterialTheme.typography.titleSmall, modifier = Modifier.weight(1f))
            Text(formatDuration(session.activeMs), style = MaterialTheme.typography.titleSmall)
        }
        // the apps' shares of the session as one bar
        Row(Modifier.fillMaxWidth().height(6.dp).clip(RoundedCornerShape(3.dp)).background(track)) {
            val total = session.activeMs.coerceAtLeast(1)
            session.apps.forEach { app ->
                val share = app.ms.toFloat() / total
                if (share > 0f) Box(Modifier.weight(share).height(6.dp).background(colors[app.name] ?: fallback))
            }
            val rest = 1f - session.apps.sumOf { it.ms }.toFloat() / total
            if (rest > 0.001f) Box(Modifier.weight(rest))
        }
        Text(
            session.apps.take(3).joinToString(" · ") { it.name } +
                (if (session.devices.size > 1) " — on ${session.devices.joinToString(", ")}" else ""),
            style = MaterialTheme.typography.bodySmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
            maxLines = 1,
            overflow = TextOverflow.Ellipsis,
        )
        AnimatedVisibility(open) {
            Column(verticalArrangement = Arrangement.spacedBy(4.dp), modifier = Modifier.padding(top = 4.dp)) {
                session.apps.forEach { app ->
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Box(Modifier.size(8.dp).clip(CircleShape).background(colors[app.name] ?: fallback))
                        Text(" ${app.name}", style = MaterialTheme.typography.bodyMedium, modifier = Modifier.weight(1f))
                        Text(formatDuration(app.ms), style = MaterialTheme.typography.bodyMedium)
                    }
                }
            }
        }
    }
}

/** The chart small, on the overview, opening the timeline. */
@OptIn(ExperimentalLayoutApi::class)
@Composable
fun TimelinePreviewCard(timeline: Timeline, onOpen: () -> Unit) {
    if (timeline.series.isEmpty()) return
    val colors = seriesColors(timeline.series)
    Card(onClick = onOpen) {
        Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text("Over time", style = MaterialTheme.typography.labelLarge, modifier = Modifier.weight(1f))
                Text(
                    "Open timeline ›",
                    style = MaterialTheme.typography.labelSmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
            AreaChart(timeline, colors, Modifier.fillMaxWidth().height(120.dp), grid = false)
            TimeAxis(timeline)
            FlowRow(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                timeline.series.take(4).forEach { s ->
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Box(Modifier.size(8.dp).clip(CircleShape).background(colors.getValue(s.name)))
                        Text(" ${s.name}", style = MaterialTheme.typography.labelSmall)
                    }
                }
            }
        }
    }
}
