package io.github.couchpotato007.wellbeing

import androidx.activity.compose.BackHandler
import androidx.compose.material.icons.Icons
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.runtime.key
import kotlinx.coroutines.delay
import androidx.compose.animation.slideInHorizontally
import androidx.compose.animation.slideOutHorizontally
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material3.Card
import androidx.compose.animation.AnimatedContent
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.FastOutSlowInEasing
import androidx.compose.animation.core.animate
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.tween
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
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
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.pager.HorizontalPager
import androidx.compose.foundation.pager.rememberPagerState
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import kotlinx.coroutines.withContext
import kotlinx.coroutines.Dispatchers
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
import androidx.compose.ui.text.drawText
import androidx.compose.ui.text.rememberTextMeasurer
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Constraints
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.platform.LocalHapticFeedback
import androidx.compose.ui.unit.Density
import androidx.compose.ui.unit.dp
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
 * The activity strips as a tab, one page per device (or day) to swipe
 * between, each a day from top to bottom. Pinch or the buttons zoom, a tap on
 * a block shows its apps below the timeline.
 */
@Composable
fun TimelineScreen(server: Server, state: DashboardState, initialPage: Int) {
    val report = state.report
    // the block on its own page, null for the timeline
    var opened by remember { mutableStateOf<Opened?>(null) }
    // the block last looked at, pointed out when coming back
    var back by remember { mutableStateOf<Segment?>(null) }

    Box(Modifier.fillMaxSize()) {
        Column(Modifier.fillMaxSize()) {
            Column(Modifier.padding(horizontal = 16.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                Text("Timeline", style = MaterialTheme.typography.headlineMedium)
                Controls(state, showDevices = false)
            }
            when {
                report == null -> Text(state.error ?: "Loading…", Modifier.padding(16.dp))
                report.strips.isEmpty() -> Text(
                    if (report.days > 1) "The timeline shows up to 31 days." else "Nothing recorded on this day.",
                    Modifier.padding(16.dp),
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
                // a new pager for another day, range or device
                else -> key(report.date, report.days, report.device) {
                    TimelineContent(server, report, initialPage, categoryColors(report), state::openDay, back) {
                        back = null
                        opened = it
                    }
                }
            }
        }

        // over the timeline, which keeps its page and scroll position below
        AnimatedVisibility(
            opened != null && report != null,
            enter = slideInHorizontally(tween(300)) { it } + fadeIn(tween(300)),
            exit = slideOutHorizontally(tween(250)) { it } + fadeOut(tween(250)),
        ) {
            // the last one stays while sliding out
            val shown = remember { mutableStateOf<Opened?>(null) }
            opened?.let { shown.value = it }
            val current = shown.value ?: return@AnimatedVisibility
            val currentReport = report ?: return@AnimatedVisibility
            Surface(Modifier.fillMaxSize()) {
                BlockDetail(server, current, currentReport, categoryColors(currentReport)) { last ->
                    back = last
                    opened = null
                }
            }
        }
    }
}

/** A block opened on its own page, with the blocks of its device to step through. */
private data class Opened(val strip: Strip, val device: String, val blocks: List<Segment>, val index: Int)

@Composable
private fun TimelineContent(
    server: Server,
    report: Report,
    initialPage: Int,
    colors: Map<String, Color>,
    onOpenDay: (String) -> Unit,
    highlight: Segment?,
    onOpen: (Opened) -> Unit,
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

    Row(Modifier.padding(start = 16.dp, end = 4.dp), verticalAlignment = Alignment.CenterVertically) {
        Text(
            if (report.days == 1) "Per device" else "Per day",
            style = MaterialTheme.typography.titleSmall,
            modifier = Modifier.weight(1f),
        )
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
            TimelinePage(
                device,
                strips[page],
                report.categoryOrder,
                report.deviceOs,
                colors,
                zoom,
                onOpenDay,
                highlight,
                onOpen,
            )
        }
    }
}

@Composable
private fun TimelinePage(
    device: String,
    strip: Strip,
    order: List<String>,
    deviceOs: Map<String, String>,
    colors: Map<String, Color>,
    zoom: Zoom,
    onOpenDay: (String) -> Unit,
    highlight: Segment?,
    onOpen: (Opened) -> Unit,
) {
    // a column per device, so a day of all devices keeps them apart
    val lanes = strip.segments.map { it.device }.distinct().sorted()
    // blocks closer than a few dp are one, too small to tell apart anyway
    val blocks = blocks(strip.segments, (GAP_DP / zoom.hourDp * HOUR_MS).toLong())
    // stands out for a moment after coming back from it
    var flash by remember(strip) { mutableStateOf<Segment?>(null) }
    val dim by animateFloatAsState(if (flash == null) 0f else 1f, tween(250), label = "dim")
    // blocks grow in from the left when the page is first shown
    val reveal = remember(strip) { Animatable(0f) }
    LaunchedEffect(strip) { reveal.animateTo(1f, tween(700, easing = FastOutSlowInEasing)) }
    val haptics = LocalHapticFeedback.current

    val scroll = rememberScrollState()
    val density = LocalDensity.current
    val yOf = { ms: Long -> with(density) { (zoom.hourDp * (ms - strip.startMs) / HOUR_MS).dp.toPx() } }
    // opens at the first activity, a bit above it
    LaunchedEffect(strip) {
        val first = strip.segments.firstOrNull() ?: return@LaunchedEffect
        scroll.animateScrollTo((yOf(first.startMs) - with(density) { 32.dp.toPx() }).toInt().coerceAtLeast(0), tween(600))
    }
    // the block stepped to on its page may be elsewhere in the day
    LaunchedEffect(highlight) {
        val block = highlight?.takeIf { it in blocks } ?: return@LaunchedEffect
        val top = yOf(block.startMs)
        if (top < scroll.value || yOf(block.endMs) > scroll.value + scroll.viewportSize) {
            scroll.animateScrollTo((top - scroll.viewportSize / 3).toInt().coerceAtLeast(0), tween(400))
        }
        flash = block
        delay(1200)
        flash = null
    }

    Column(Modifier.fillMaxSize()) {
        PageSummary(strip, order, colors, reveal.value, onOpenDay)

        if (lanes.size > 1) {
            Row(Modifier.padding(start = GUTTER_DP.dp, end = 16.dp, bottom = 4.dp)) {
                lanes.forEach { lane ->
                    Column(Modifier.weight(1f).padding(horizontal = 2.dp)) {
                        Text(lane, style = MaterialTheme.typography.labelMedium, maxLines = 1, overflow = TextOverflow.Ellipsis)
                        deviceOs[lane]?.let {
                            Text(
                                osName(it),
                                style = MaterialTheme.typography.labelSmall,
                                color = MaterialTheme.colorScheme.onSurfaceVariant,
                                maxLines = 1,
                            )
                        }
                    }
                }
            }
        }

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
            DayCanvas(strip, lanes, blocks, colors, zoom.hourDp, flash, dim, reveal.value) { tapped ->
                if (tapped == null) return@DayCanvas
                haptics.performHapticFeedback(HapticFeedbackType.TextHandleMove)
                // the arrows on its page step through the blocks of the same device
                val sameDevice = blocks.filter { it.device == tapped.device }
                onOpen(Opened(strip, tapped.device.ifEmpty { device }, sameDevice, sameDevice.indexOf(tapped)))
            }
        }
    }
}

/** Left of the lanes, for the hour labels. */
private const val GUTTER_DP = 60

/** Blocks of a device and category less than this apart are drawn as one. */
private const val GAP_DP = 6f

/** Taps this close to a block still hit it. */
private const val TOUCH_DP = 24

/** Segments of the same device and category closer than [gapMs] merged, sorted by start. */
private fun blocks(segments: List<Segment>, gapMs: Long): List<Segment> =
    segments.groupBy { it.device }.values.flatMap { group ->
        val merged = mutableListOf<Segment>()
        group.sortedBy { it.startMs }.forEach { s ->
            val last = merged.lastOrNull()
            if (last != null && last.category == s.category && s.startMs <= last.endMs + gapMs) {
                merged[merged.lastIndex] = last.copy(endMs = maxOf(last.endMs, s.endMs))
            } else {
                merged.add(s)
            }
        }
        merged
    }.sortedBy { it.startMs }

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
            "Tap a block to open it · pinch to zoom · swipe for the next " +
                if (strip.date.isEmpty()) "device" else "day",
            style = MaterialTheme.typography.labelSmall,
            color = muted,
        )
    }
}

/** The day from top to bottom, hour lines on the left, a lane of blocks per device. */
@Composable
private fun DayCanvas(
    strip: Strip,
    lanes: List<String>,
    blocks: List<Segment>,
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
            .pointerInput(strip, lanes, blocks, hourDp) {
                detectTapGestures { offset ->
                    val geometry = Geometry(this, size.width.toFloat(), size.height.toFloat(), strip, lanes.size)
                    val lane = geometry.laneAt(offset.x)
                    // the nearest block of the lane, a short one needn't be hit exactly
                    val nearest = blocks
                        .filter { lanes.indexOf(it.device) == lane }
                        .map { block ->
                            val top = geometry.y(block.startMs)
                            val bottom = top + geometry.height(block)
                            block to when {
                                offset.y < top -> top - offset.y
                                offset.y > bottom -> offset.y - bottom
                                else -> 0f
                            }
                        }
                        .minByOrNull { it.second }
                    onTap(nearest?.takeIf { it.second <= TOUCH_DP.dp.toPx() }?.first)
                }
            }
    ) {
        val geometry = Geometry(this, size.width, size.height, strip, lanes.size)

        // an hour line with label every hour, or every 3 when zoomed out
        val every = if (hourDp >= 36f) 1 else 3
        for (hour in 0..hours.toInt()) {
            val lineY = geometry.y(strip.startMs + hour * HOUR_MS)
            if (hour % every == 0) {
                val label = measurer.measure("%02d:00".format(hour % 24), labelStyle)
                drawText(label, topLeft = Offset(12.dp.toPx(), lineY - label.size.height / 2))
            }
            drawLine(line, Offset(geometry.gutter, lineY), Offset(geometry.right, lineY), strokeWidth = 1.dp.toPx())
            if (hourDp >= 120f && hour < hours.toInt()) {
                val half = geometry.y(strip.startMs + hour * HOUR_MS + HOUR_MS / 2)
                drawLine(
                    line.copy(alpha = 0.4f),
                    Offset(geometry.gutter, half),
                    Offset(geometry.right, half),
                    strokeWidth = 1.dp.toPx(),
                )
            }
        }

        val width = (geometry.laneWidth - 4.dp.toPx()) * reveal
        blocks.forEach { block ->
            val isSelected = block == selected
            val color = colors[block.category] ?: Color.Gray
            val left = geometry.laneLeft(lanes.indexOf(block.device)) + 2.dp.toPx()
            val y0 = geometry.y(block.startMs)
            val h = geometry.height(block)
            // the selected block steps out a bit, the others fade
            val grow = if (isSelected) 3.dp.toPx() * dim else 0f
            drawRoundRect(
                color.copy(alpha = if (isSelected) 1f else 1f - 0.6f * dim),
                topLeft = Offset(left - grow, y0 - grow),
                size = Size(width + 2 * grow, h + 2 * grow),
                cornerRadius = CornerRadius(4.dp.toPx()),
            )
            if (isSelected) {
                drawRoundRect(
                    outline,
                    topLeft = Offset(left - grow, y0 - grow),
                    size = Size(width + 2 * grow, h + 2 * grow),
                    cornerRadius = CornerRadius(4.dp.toPx()),
                    style = Stroke(2.dp.toPx()),
                )
            }
            // names in blocks that have room for them
            if (h >= 20.dp.toPx() && width > 48.dp.toPx()) {
                val text = block.category + "  " + clock(block.startMs - strip.startMs) + "–" +
                    clock(block.endMs - strip.startMs)
                val layout = measurer.measure(
                    text,
                    blockStyle,
                    overflow = TextOverflow.Ellipsis,
                    maxLines = 1,
                    constraints = Constraints(maxWidth = (width - 12.dp.toPx()).toInt().coerceAtLeast(0)),
                )
                drawText(layout, topLeft = Offset(left + 6.dp.toPx(), y0 + 3.dp.toPx()))
            }
        }

        if (now in strip.startMs until strip.endMs) {
            val nowY = geometry.y(now)
            drawLine(nowColor, Offset(geometry.gutter, nowY), Offset(geometry.right, nowY), strokeWidth = 2.dp.toPx())
            drawCircle(nowColor, 4.dp.toPx(), Offset(geometry.gutter, nowY))
        }
    }
}

/** Where things go on the canvas, the same for drawing and for taps. */
private class Geometry(density: Density, width: Float, height: Float, private val strip: Strip, private val lanes: Int) {
    private val top = with(density) { 8.dp.toPx() }
    private val inner = height - 2 * top
    private val minHeight = with(density) { 4.dp.toPx() }
    private val length = (strip.endMs - strip.startMs).coerceAtLeast(1).toFloat()
    val gutter = with(density) { GUTTER_DP.dp.toPx() }
    val right = width - with(density) { 16.dp.toPx() }
    val laneWidth = (right - gutter) / lanes.coerceAtLeast(1)

    fun y(ms: Long) = top + inner * (ms - strip.startMs) / length

    fun height(block: Segment) = (y(block.endMs) - y(block.startMs)).coerceAtLeast(minHeight)

    fun laneLeft(lane: Int) = gutter + lane * laneWidth

    fun laneAt(x: Float) = ((x - gutter) / laneWidth).toInt().coerceIn(0, (lanes - 1).coerceAtLeast(0))
}

/**
 * A block on its own page: when it was, where in the day, and its apps and
 * window titles from the server. Swipe or the arrows step to the device's
 * block before or after, [onBack] gets the one shown last.
 */
@Composable
private fun BlockDetail(server: Server, opened: Opened, report: Report, colors: Map<String, Color>, onBack: (Segment) -> Unit) {
    val blocks = opened.blocks
    val pager = rememberPagerState(opened.index.coerceIn(0, blocks.lastIndex)) { blocks.size }
    val scope = rememberCoroutineScope()
    val back = { onBack(blocks[pager.currentPage]) }
    BackHandler(onBack = back)
    val os = report.deviceOs[opened.device]

    Column(Modifier.fillMaxSize()) {
        Row(Modifier.padding(horizontal = 4.dp, vertical = 4.dp), verticalAlignment = Alignment.CenterVertically) {
            IconButton(onClick = back) { Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "Back") }
            Column(Modifier.weight(1f)) {
                Text(opened.device + (os?.let { " · " + osName(it) } ?: ""), style = MaterialTheme.typography.titleMedium)
                Text(
                    if (opened.strip.date.isEmpty()) period(report) else opened.strip.label,
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
            TextButton(
                enabled = pager.currentPage > 0,
                onClick = { scope.launch { pager.animateScrollToPage(pager.currentPage - 1) } },
            ) { Text("‹", style = MaterialTheme.typography.titleLarge) }
            Text("${pager.currentPage + 1} / ${blocks.size}", style = MaterialTheme.typography.labelMedium)
            TextButton(
                enabled = pager.currentPage < blocks.lastIndex,
                onClick = { scope.launch { pager.animateScrollToPage(pager.currentPage + 1) } },
            ) { Text("›", style = MaterialTheme.typography.titleLarge) }
        }

        HorizontalPager(pager, Modifier.fillMaxSize(), beyondViewportPageCount = 1) { page ->
            BlockPage(server, opened.device, opened.strip, blocks, blocks[page], colors)
        }
    }
}

@Composable
private fun BlockPage(
    server: Server,
    device: String,
    strip: Strip,
    blocks: List<Segment>,
    block: Segment,
    colors: Map<String, Color>,
) {
    val color = colors[block.category] ?: Color.Gray
    val length = (block.endMs - block.startMs).coerceAtLeast(1)
    var usage by remember(block) { mutableStateOf<BlockUsage?>(null) }
    var error by remember(block) { mutableStateOf<String?>(null) }
    var retry by remember(block) { mutableStateOf(0) }
    LaunchedEffect(block, retry) {
        error = null
        withContext(Dispatchers.IO) {
            runCatching { Stats.block(server, device, block.category, block.startMs, block.endMs) }
        }
            .onSuccess { usage = it }
            .onFailure { error = Sync.describe(it) }
    }

    Column(
        Modifier
            .fillMaxSize()
            .verticalScroll(rememberScrollState())
            .padding(horizontal = 16.dp, vertical = 8.dp),
        verticalArrangement = Arrangement.spacedBy(16.dp),
    ) {
        // the block in its category's color
        Surface(color = color, contentColor = Color.White, shape = RoundedCornerShape(24.dp)) {
            Column(Modifier.fillMaxWidth().padding(20.dp), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                Text(block.category, style = MaterialTheme.typography.titleLarge)
                Text(formatDuration(length), style = MaterialTheme.typography.displaySmall)
                Text(
                    clock(block.startMs - strip.startMs) + " – " + clock(block.endMs - strip.startMs),
                    style = MaterialTheme.typography.titleMedium,
                )
            }
        }

        DayPosition(strip, blocks, block, colors)

        val loaded = usage
        AnimatedContent(Triple(loaded, error, retry), label = "usage") { (loaded, error, _) ->
            when {
                error != null -> Card(Modifier.fillMaxWidth()) {
                    Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                        Text("Could not load the apps: $error", style = MaterialTheme.typography.bodyMedium)
                        TextButton(onClick = { retry++ }) { Text("Retry") }
                    }
                }
                loaded == null -> Box(Modifier.fillMaxWidth().height(120.dp), contentAlignment = Alignment.Center) {
                    CircularProgressIndicator(Modifier.size(28.dp), strokeWidth = 3.dp)
                }
                else -> Column(verticalArrangement = Arrangement.spacedBy(16.dp)) {
                    BlockList("Apps", loaded.apps, length, color)
                    BlockList("Window titles", loaded.titles, length, color)
                }
            }
        }
    }
}

/** The day of the device as one bar, the block stands out, its neighbors are faint. */
@Composable
private fun DayPosition(strip: Strip, blocks: List<Segment>, block: Segment, colors: Map<String, Color>) {
    val track = MaterialTheme.colorScheme.surfaceVariant
    val muted = MaterialTheme.colorScheme.onSurfaceVariant
    val marker = MaterialTheme.colorScheme.onSurface
    val length = (strip.endMs - strip.startMs).coerceAtLeast(1).toFloat()
    val grow = remember(block) { Animatable(0f) }
    LaunchedEffect(block) { grow.animateTo(1f, tween(500, easing = FastOutSlowInEasing)) }

    Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
        Text("In the day", style = MaterialTheme.typography.labelLarge, color = muted)
        Canvas(Modifier.fillMaxWidth().height(36.dp)) {
            val barTop = 8.dp.toPx()
            val barHeight = size.height - 2 * barTop
            drawRoundRect(track, Offset(0f, barTop), Size(size.width, barHeight), CornerRadius(6.dp.toPx()))
            val x = { ms: Long -> size.width * (ms - strip.startMs) / length }
            blocks.forEach { b ->
                val w = (x(b.endMs) - x(b.startMs)).coerceAtLeast(1.dp.toPx())
                drawRect((colors[b.category] ?: Color.Gray).copy(alpha = 0.3f), Offset(x(b.startMs), barTop), Size(w, barHeight))
            }
            // the block grows out of its middle to full height
            val w = (x(block.endMs) - x(block.startMs)).coerceAtLeast(4.dp.toPx())
            val h = barHeight + (size.height - barHeight) * grow.value
            drawRoundRect(
                colors[block.category] ?: Color.Gray,
                Offset(x(block.startMs), (size.height - h) / 2),
                Size(w, h),
                CornerRadius(3.dp.toPx()),
            )
            drawRoundRect(
                marker,
                Offset(x(block.startMs), (size.height - h) / 2),
                Size(w, h),
                CornerRadius(3.dp.toPx()),
                style = Stroke(1.5.dp.toPx()),
            )
        }
        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
            listOf("0", "6", "12", "18", "24").forEach {
                Text(it, style = MaterialTheme.typography.labelSmall, color = muted)
            }
        }
    }
}

/** Rows with a meter and their share of the block's [length]. */
@Composable
private fun BlockList(title: String, items: List<UsageItem>, length: Long, color: Color) {
    if (items.isEmpty()) return
    val max = items.maxOf { it.ms }.coerceAtLeast(1)
    val track = MaterialTheme.colorScheme.surfaceVariant
    Card(Modifier.fillMaxWidth()) {
        Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
            Text(title, style = MaterialTheme.typography.titleSmall)
            items.forEach { item ->
                Column(verticalArrangement = Arrangement.spacedBy(3.dp)) {
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Text(item.name, maxLines = 2, overflow = TextOverflow.Ellipsis, modifier = Modifier.weight(1f))
                        Column(Modifier.padding(start = 12.dp), horizontalAlignment = Alignment.End) {
                            Text(formatDuration(item.ms), style = MaterialTheme.typography.bodyMedium)
                            Text(
                                "${(item.ms * 100 / length).coerceAtMost(100)}%",
                                style = MaterialTheme.typography.labelSmall,
                                color = MaterialTheme.colorScheme.onSurfaceVariant,
                            )
                        }
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
                    Box(Modifier.fillMaxWidth().height(6.dp).clip(RoundedCornerShape(3.dp)).background(track)) {
                        Box(
                            Modifier
                                .fillMaxWidth(item.ms.toFloat() / max)
                                .height(6.dp)
                                .clip(RoundedCornerShape(3.dp))
                                .background(color)
                        )
                    }
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
