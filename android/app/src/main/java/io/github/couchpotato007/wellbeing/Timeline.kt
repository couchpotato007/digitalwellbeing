package io.github.couchpotato007.wellbeing

import androidx.compose.animation.AnimatedContent
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.FastOutSlowInEasing
import androidx.compose.animation.core.MutableTransitionState
import androidx.compose.animation.core.animate
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.tween
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.scaleIn
import androidx.compose.animation.scaleOut
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.gestures.awaitEachGesture
import androidx.compose.foundation.gestures.awaitFirstDown
import androidx.compose.foundation.gestures.calculateCentroid
import androidx.compose.foundation.gestures.calculateZoom
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeDrawingPadding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.pager.HorizontalPager
import androidx.compose.foundation.pager.rememberPagerState
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import kotlinx.coroutines.withContext
import kotlinx.coroutines.Dispatchers
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ScrollableTabRow
import androidx.compose.material3.Surface
import androidx.compose.material3.Tab
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.runtime.snapshotFlow
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.input.pointer.PointerEventPass
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.drawText
import androidx.compose.ui.text.rememberTextMeasurer
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Constraints
import androidx.compose.ui.unit.dp
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.launch
import kotlin.math.abs

private const val HOUR_MS = 3_600_000L

/** Height of an hour in dp, between these. */
private const val MIN_HOUR_DP = 24f
private const val MAX_HOUR_DP = 320f

/** The zoom, shared by all pages so swiping keeps it. */
private class Zoom {
    var hourDp by mutableFloatStateOf(64f)
}

/**
 * The activity strips full screen, one page per device (or day) to swipe
 * between, each a day from top to bottom. Pinch or the buttons zoom, a tap on
 * a block shows what it was. [colors] has the color of every category.
 */
@Composable
fun TimelineDialog(
    server: Server,
    report: Report,
    subtitle: String,
    initialPage: Int,
    colors: Map<String, Color>,
    onOpenDay: (String) -> Unit,
    onDismiss: () -> Unit,
) {
    val visible = remember { MutableTransitionState(false).apply { targetState = true } }
    // dismissed once the exit animation is done
    LaunchedEffect(Unit) {
        snapshotFlow { !visible.targetState && visible.isIdle }.first { it }
        onDismiss()
    }
    val close = { visible.targetState = false }

    Dialog(
        onDismissRequest = close,
        properties = DialogProperties(usePlatformDefaultWidth = false, decorFitsSystemWindows = false),
    ) {
        AnimatedVisibility(
            visible,
            enter = fadeIn(tween(220)) + scaleIn(tween(260), initialScale = 0.9f),
            exit = fadeOut(tween(180)) + scaleOut(tween(180), targetScale = 0.9f),
        ) {
            Surface(Modifier.fillMaxSize()) {
                Column(Modifier.safeDrawingPadding()) {
                    TimelineContent(server, report, subtitle, initialPage, colors, onClose = close, onOpenDay = {
                        onOpenDay(it)
                        close()
                    })
                }
            }
        }
    }
}

@Composable
private fun TimelineContent(
    server: Server,
    report: Report,
    subtitle: String,
    initialPage: Int,
    colors: Map<String, Color>,
    onClose: () -> Unit,
    onOpenDay: (String) -> Unit,
) {
    val strips = report.strips
    val pager = rememberPagerState(initialPage.coerceIn(0, strips.lastIndex)) { strips.size }
    val scope = rememberCoroutineScope()
    val zoom = remember { Zoom() }
    val zoomTo = { target: Float ->
        scope.launch {
            animate(zoom.hourDp, target.coerceIn(MIN_HOUR_DP, MAX_HOUR_DP), animationSpec = tween(300)) { value, _ ->
                zoom.hourDp = value
            }
        }
    }

    Row(Modifier.padding(horizontal = 4.dp), verticalAlignment = Alignment.CenterVertically) {
        TextButton(onClick = onClose) { Text("✕", style = MaterialTheme.typography.titleLarge) }
        Column(Modifier.weight(1f)) {
            Text(
                if (report.days == 1) "Activity per device" else "Activity per day",
                style = MaterialTheme.typography.titleMedium,
            )
            Text(subtitle, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
        TextButton(enabled = zoom.hourDp > MIN_HOUR_DP, onClick = { zoomTo(zoom.hourDp / 1.6f) }) {
            Text("−", style = MaterialTheme.typography.titleLarge)
        }
        TextButton(enabled = zoom.hourDp < MAX_HOUR_DP, onClick = { zoomTo(zoom.hourDp * 1.6f) }) {
            Text("+", style = MaterialTheme.typography.titleLarge)
        }
    }

    ScrollableTabRow(selectedTabIndex = pager.currentPage, edgePadding = 12.dp) {
        strips.forEachIndexed { i, strip ->
            // rows of a day have a date, rows of a device the device's name
            val os = if (strip.date.isEmpty()) report.deviceOs[strip.label] else null
            Tab(
                selected = pager.currentPage == i,
                onClick = { scope.launch { pager.animateScrollToPage(i) } },
                text = {
                    Column(horizontalAlignment = Alignment.CenterHorizontally) {
                        Text(strip.label, maxLines = 1)
                        if (os != null) {
                            Text(
                                os,
                                style = MaterialTheme.typography.labelSmall,
                                color = MaterialTheme.colorScheme.onSurfaceVariant,
                                maxLines = 1,
                            )
                        }
                    }
                },
            )
        }
    }

    HorizontalPager(pager, Modifier.fillMaxSize(), beyondViewportPageCount = 1) { page ->
        Box(
            Modifier.graphicsLayer {
                // pages shrink and fade a little while swiped away
                val away = abs(pager.currentPage - page + pager.currentPageOffsetFraction).coerceIn(0f, 1f)
                alpha = 1f - 0.5f * away
                scaleX = 1f - 0.08f * away
                scaleY = 1f - 0.08f * away
            }
        ) {
            // rows of a device are one device, rows of a day the devices picked
            val device = if (strips[page].date.isEmpty()) strips[page].label else report.device
            TimelinePage(server, device, strips[page], report.categoryOrder, colors, zoom, onOpenDay)
        }
    }
}

@Composable
private fun TimelinePage(
    server: Server,
    device: String,
    strip: Strip,
    order: List<String>,
    colors: Map<String, Color>,
    zoom: Zoom,
    onOpenDay: (String) -> Unit,
) {
    // index into strip.segments of the block whose sheet is open
    var selected by remember(strip) { mutableStateOf<Int?>(null) }
    val dim by animateFloatAsState(if (selected == null) 0f else 1f, tween(250), label = "dim")
    // blocks grow in from the left when the page is first shown
    val reveal = remember(strip) { Animatable(0f) }
    LaunchedEffect(strip) { reveal.animateTo(1f, tween(700, easing = FastOutSlowInEasing)) }

    val scroll = rememberScrollState()
    val density = LocalDensity.current
    val scrollTo = { ms: Long ->
        with(density) { (zoom.hourDp * (ms - strip.startMs) / HOUR_MS - 32).dp.toPx() }.toInt().coerceAtLeast(0)
    }
    // opens at the first activity, a bit above it
    LaunchedEffect(strip) {
        val first = strip.segments.firstOrNull() ?: return@LaunchedEffect
        scroll.animateScrollTo(scrollTo(first.startMs), tween(600))
    }
    // the picked block moves to the top, above the sheet
    LaunchedEffect(selected) {
        val segment = selected?.let { strip.segments[it] } ?: return@LaunchedEffect
        scroll.animateScrollTo(scrollTo(segment.startMs), tween(400))
    }

    Column(Modifier.fillMaxSize()) {
        PageSummary(strip, order, colors, reveal.value, onOpenDay)

        Box(
            Modifier
                .weight(1f)
                .fillMaxWidth()
                .pinchToZoom { factor, centroidY ->
                    val before = zoom.hourDp
                    zoom.hourDp = (before * factor).coerceIn(MIN_HOUR_DP, MAX_HOUR_DP)
                    // keeps the point between the fingers in place
                    val applied = zoom.hourDp / before
                    scroll.dispatchRawDelta((scroll.value + centroidY) * applied - centroidY - scroll.value)
                }
                .verticalScroll(scroll)
        ) {
            DayCanvas(strip, colors, zoom.hourDp, selected?.let { strip.segments[it] }, dim, reveal.value) { tapped ->
                selected = tapped?.let { strip.segments.indexOf(it) }
            }
        }
    }

    selected?.let { index ->
        BlockSheet(
            server,
            device,
            strip,
            index,
            colors,
            onSelect = { selected = it },
            onDismiss = { selected = null },
        )
    }
}

/** Active time, first and last activity, and the share of each category as one bar. */
@Composable
private fun PageSummary(
    strip: Strip,
    order: List<String>,
    colors: Map<String, Color>,
    reveal: Float,
    onOpenDay: (String) -> Unit,
) {
    val byCategory = strip.segments
        .groupBy { topLevel(it.category) }
        .mapValues { (_, segments) -> segments.sumOf { it.endMs - it.startMs } }
        .entries.sortedWith(compareBy({ colorSlot(order, it.key) ?: Int.MAX_VALUE }, { -it.value }))
    val sum = byCategory.sumOf { it.value }.coerceAtLeast(1)
    val track = MaterialTheme.colorScheme.surfaceVariant
    val muted = MaterialTheme.colorScheme.onSurfaceVariant

    Column(Modifier.padding(horizontal = 16.dp, vertical = 8.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
        Row(verticalAlignment = Alignment.Bottom) {
            Text(formatDuration(activeMs(strip.segments)), style = MaterialTheme.typography.headlineSmall)
            Spacer(Modifier.width(8.dp))
            Text(
                strip.segments.firstOrNull()?.let {
                    clock(it.startMs - strip.startMs) + " – " + clock(strip.segments.maxOf { s -> s.endMs } - strip.startMs)
                } ?: "nothing recorded",
                style = MaterialTheme.typography.bodySmall,
                color = muted,
                modifier = Modifier.weight(1f).padding(bottom = 4.dp),
            )
            if (strip.date.isNotEmpty()) TextButton(onClick = { onOpenDay(strip.date) }) { Text("Open day") }
        }
        Canvas(Modifier.fillMaxWidth().height(8.dp).clip(RoundedCornerShape(4.dp)).background(track)) {
            var x = 0f
            byCategory.forEach { (category, ms) ->
                val w = size.width * ms / sum * reveal
                drawRect(colors[category] ?: Color.Gray, Offset(x, 0f), Size(w, size.height))
                x += w
            }
        }
        Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
            byCategory.take(3).forEach { (category, ms) ->
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Box(Modifier.size(8.dp).clip(RoundedCornerShape(2.dp)).background(colors[category] ?: Color.Gray))
                    Text(
                        " $category ${ms * 100 / sum}%",
                        style = MaterialTheme.typography.labelSmall,
                        color = muted,
                        maxLines = 1,
                    )
                }
            }
        }
        Text(
            "Tap a block to see its apps · pinch to zoom",
            style = MaterialTheme.typography.labelSmall,
            color = muted,
        )
    }
}

/** The day from top to bottom, hour lines on the left, a block per segment. */
@Composable
private fun DayCanvas(
    strip: Strip,
    colors: Map<String, Color>,
    hourDp: Float,
    selected: Segment?,
    dim: Float,
    reveal: Float,
    onTap: (Segment?) -> Unit,
) {
    val length = (strip.endMs - strip.startMs).coerceAtLeast(1)
    val hours = length.toFloat() / HOUR_MS
    val measurer = rememberTextMeasurer()
    val line = MaterialTheme.colorScheme.outlineVariant
    val muted = MaterialTheme.colorScheme.onSurfaceVariant
    val nowColor = MaterialTheme.colorScheme.error
    val outline = MaterialTheme.colorScheme.onSurface
    val labelStyle = MaterialTheme.typography.labelSmall.copy(color = muted)
    val blockStyle = MaterialTheme.typography.labelMedium.copy(color = Color.White)
    val now = System.currentTimeMillis()

    Canvas(
        Modifier
            .fillMaxWidth()
            .height((hourDp * hours).dp + 16.dp)
            .pointerInput(strip, hourDp) {
                detectTapGestures { offset ->
                    val top = 8.dp.toPx()
                    val msPerPx = length / (size.height - 2 * top)
                    val at = strip.startMs + ((offset.y - top) * msPerPx).toLong()
                    // short segments are hard to hit, so a few dp around count
                    val slack = (8.dp.toPx() * msPerPx).toLong()
                    onTap(
                        strip.segments.firstOrNull { at in it.startMs until it.endMs }
                            ?: strip.segments
                                .filter { at in it.startMs - slack until it.endMs + slack }
                                .minByOrNull { minOf(abs(at - it.startMs), abs(at - it.endMs)) }
                    )
                }
            }
    ) {
        val top = 8.dp.toPx()
        val height = size.height - 2 * top
        val gutter = 52.dp.toPx()
        val right = size.width - 16.dp.toPx()
        val y = { ms: Long -> top + height * (ms - strip.startMs) / length }

        // an hour line with label every hour, or every 3 when zoomed out
        val every = if (hourDp >= 36f) 1 else 3
        for (hour in 0..hours.toInt()) {
            val lineY = top + height * hour / hours
            if (hour % every == 0) {
                val label = measurer.measure("%02d:00".format(hour % 24), labelStyle)
                drawText(label, topLeft = Offset(12.dp.toPx(), lineY - label.size.height / 2))
            }
            drawLine(line, Offset(gutter, lineY), Offset(right, lineY), strokeWidth = 1.dp.toPx())
            if (hourDp >= 120f && hour < hours.toInt()) {
                val half = lineY + height / hours / 2
                drawLine(line.copy(alpha = 0.4f), Offset(gutter, half), Offset(right, half), strokeWidth = 1.dp.toPx())
            }
        }

        val left = gutter + 8.dp.toPx()
        val fullWidth = (right - left) * reveal
        strip.segments.forEach { s ->
            val isSelected = s == selected
            val color = colors[s.category] ?: Color.Gray
            val y0 = y(s.startMs)
            val h = (y(s.endMs) - y0).coerceAtLeast(2.dp.toPx())
            // the selected block steps out a bit, the others fade
            val grow = if (isSelected) 4.dp.toPx() * dim else 0f
            drawRoundRect(
                color.copy(alpha = if (isSelected) 1f else 1f - 0.6f * dim),
                topLeft = Offset(left - grow, y0),
                size = Size(fullWidth + 2 * grow, h),
                cornerRadius = CornerRadius(4.dp.toPx()),
            )
            if (isSelected) {
                drawRoundRect(
                    outline,
                    topLeft = Offset(left - grow, y0),
                    size = Size(fullWidth + 2 * grow, h),
                    cornerRadius = CornerRadius(4.dp.toPx()),
                    style = Stroke(2.dp.toPx()),
                )
            }
            // names in blocks that have room for them
            if (h >= 20.dp.toPx() && fullWidth > 48.dp.toPx()) {
                val text = s.category + "  " + clock(s.startMs - strip.startMs) + "–" + clock(s.endMs - strip.startMs)
                val layout = measurer.measure(
                    text,
                    blockStyle,
                    overflow = TextOverflow.Ellipsis,
                    maxLines = 1,
                    constraints = Constraints(maxWidth = (fullWidth - 12.dp.toPx()).toInt().coerceAtLeast(0)),
                )
                drawText(layout, topLeft = Offset(left + 6.dp.toPx(), y0 + 3.dp.toPx()))
            }
        }

        if (now in strip.startMs until strip.endMs) {
            val nowY = y(now)
            drawLine(nowColor, Offset(gutter, nowY), Offset(right, nowY), strokeWidth = 2.dp.toPx())
            drawCircle(nowColor, 4.dp.toPx(), Offset(gutter, nowY))
        }
    }
}

/**
 * The apps and window titles of a block, loaded from the server, with
 * buttons to step to the block before or after.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun BlockSheet(
    server: Server,
    device: String,
    strip: Strip,
    index: Int,
    colors: Map<String, Color>,
    onSelect: (Int) -> Unit,
    onDismiss: () -> Unit,
) {
    val segment = strip.segments[index]
    val color = colors[segment.category] ?: Color.Gray
    var usage by remember(segment) { mutableStateOf<BlockUsage?>(null) }
    var error by remember(segment) { mutableStateOf<String?>(null) }
    LaunchedEffect(segment) {
        withContext(Dispatchers.IO) {
            runCatching { Stats.block(server, device, segment.category, segment.startMs, segment.endMs) }
        }
            .onSuccess { usage = it }
            .onFailure { error = it.message ?: it.toString() }
    }

    ModalBottomSheet(onDismissRequest = onDismiss, sheetState = rememberModalBottomSheetState()) {
        Column(
            Modifier
                .padding(horizontal = 20.dp)
                .padding(bottom = 24.dp)
                .verticalScroll(rememberScrollState()),
            verticalArrangement = Arrangement.spacedBy(16.dp),
        ) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Box(Modifier.size(width = 6.dp, height = 40.dp).clip(RoundedCornerShape(3.dp)).background(color))
                Column(Modifier.weight(1f).padding(start = 12.dp)) {
                    Text(segment.category, style = MaterialTheme.typography.titleLarge)
                    Text(
                        clock(segment.startMs - strip.startMs) + " – " + clock(segment.endMs - strip.startMs) +
                            " · " + formatDuration(segment.endMs - segment.startMs),
                        style = MaterialTheme.typography.bodyMedium,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
                TextButton(enabled = index > 0, onClick = { onSelect(index - 1) }) {
                    Text("‹", style = MaterialTheme.typography.titleLarge)
                }
                TextButton(enabled = index < strip.segments.lastIndex, onClick = { onSelect(index + 1) }) {
                    Text("›", style = MaterialTheme.typography.titleLarge)
                }
            }

            val loaded = usage
            AnimatedContent(loaded to error, label = "block") { (loaded, error) ->
                when {
                    error != null -> Text("Could not load the apps: $error", style = MaterialTheme.typography.bodySmall)
                    loaded == null -> Box(Modifier.fillMaxWidth().height(96.dp), contentAlignment = Alignment.Center) {
                        CircularProgressIndicator(Modifier.size(24.dp), strokeWidth = 2.dp)
                    }
                    else -> Column(verticalArrangement = Arrangement.spacedBy(16.dp)) {
                        BlockList("Apps", loaded.apps, color)
                        BlockList("Window titles", loaded.titles, color)
                    }
                }
            }
        }
    }
}

/** Rows with a meter, like the dashboard's lists but without a card. */
@Composable
private fun BlockList(title: String, items: List<UsageItem>, color: Color) {
    if (items.isEmpty()) return
    val max = items.maxOf { it.ms }.coerceAtLeast(1)
    val track = MaterialTheme.colorScheme.surfaceVariant
    Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
        Text(title, style = MaterialTheme.typography.labelLarge, color = MaterialTheme.colorScheme.onSurfaceVariant)
        items.forEach { item ->
            Column(verticalArrangement = Arrangement.spacedBy(3.dp)) {
                Row {
                    Text(item.name, maxLines = 1, overflow = TextOverflow.Ellipsis, modifier = Modifier.weight(1f))
                    Text(formatDuration(item.ms), modifier = Modifier.padding(start = 12.dp))
                }
                if (item.detail.isNotEmpty()) {
                    Text(
                        item.detail,
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
                            .background(color)
                    )
                }
            }
        }
    }
}

/**
 * Two fingers zoom with the factor and the y of their center, one finger is
 * left to the scrolling inside.
 */
private fun Modifier.pinchToZoom(onZoom: (Float, Float) -> Unit) = pointerInput(Unit) {
    awaitEachGesture {
        awaitFirstDown(requireUnconsumed = false, pass = PointerEventPass.Initial)
        do {
            val event = awaitPointerEvent(PointerEventPass.Initial)
            if (event.changes.count { it.pressed } >= 2) {
                val factor = event.calculateZoom()
                if (factor != 1f) {
                    onZoom(factor, event.calculateCentroid().y)
                    event.changes.forEach { it.consume() }
                }
            }
        } while (event.changes.any { it.pressed })
    }
}

/** Length of the union of segments sorted by start, devices used at once count once. */
private fun activeMs(segments: List<Segment>): Long {
    var total = 0L
    var reach = Long.MIN_VALUE
    segments.sortedBy { it.startMs }.forEach { s ->
        if (s.endMs > reach) {
            total += s.endMs - maxOf(s.startMs, reach)
            reach = s.endMs
        }
    }
    return total
}

/** Time of day of `ms` after midnight, "07:05", like dashboard.clock. */
private fun clock(ms: Long): String {
    val minutes = ms / 60_000
    return "%02d:%02d".format(minutes / 60, minutes % 60)
}
