package io.github.couchpotato007.wellbeing

import android.content.Intent
import android.os.Bundle
import android.provider.Settings as AndroidSettings
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.compose.animation.AnimatedContent
import androidx.compose.animation.core.tween
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.togetherWith
import androidx.compose.foundation.layout.consumeWindowInsets
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.DateRange
import androidx.compose.material.icons.filled.Home
import androidx.compose.material.icons.filled.Settings
import androidx.compose.material3.Icon
import androidx.compose.material3.NavigationBar
import androidx.compose.material3.NavigationBarItem
import androidx.compose.material3.Scaffold
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.compose.LifecycleEventEffect
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.pulltorefresh.PullToRefreshBox
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.snapshotFlow
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.launch
import kotlinx.coroutines.withTimeoutOrNull
import kotlinx.coroutines.withContext
import java.time.LocalDate
import java.time.format.TextStyle
import java.util.Locale

class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()
        setContent {
            MaterialTheme(colorScheme = if (isSystemInDarkTheme()) darkColorScheme() else lightColorScheme()) {
                Surface(Modifier.fillMaxSize()) { App() }
            }
        }
    }
}

private enum class Tab(val label: String, val icon: ImageVector) {
    Overview("Overview", Icons.Filled.Home),
    Timeline("Timeline", Icons.Filled.DateRange),
    Settings("Settings", Icons.Filled.Settings),
}

@Composable
private fun App() {
    val context = LocalContext.current
    val settings = remember { Settings(context) }
    var hasAccess by remember { mutableStateOf(Usage.hasAccess(context)) }
    var server by remember { mutableStateOf(settings.server) }
    var lastSync by remember { mutableStateOf(settings.lastSync) }
    // bumped to reload the chart and status
    var refresh by remember { mutableIntStateOf(0) }
    var tab by rememberSaveable { mutableStateOf(Tab.Overview) }

    LifecycleEventEffect(Lifecycle.Event.ON_RESUME) {
        hasAccess = Usage.hasAccess(context)
        lastSync = settings.lastSync
        refresh++
    }
    // collecting runs without a server too, it keeps what Android would forget
    LaunchedEffect(hasAccess) {
        if (hasAccess) Sync.schedule(context)
    }

    val current = server
    // pulled down: upload what the phone has (or only collect without a
    // server), then load again
    val reload: suspend () -> Unit = {
        withContext(Dispatchers.IO) {
            runCatching { if (current != null) Sync.run(context) else Sync.collect(context) }
        }
        lastSync = settings.lastSync
        refresh++
    }
    // with a server, all devices from there, otherwise only this phone
    val dashboard = current?.let { rememberDashboard(it, refresh) }

    Scaffold(
        bottomBar = {
            NavigationBar {
                Tab.entries.forEach {
                    NavigationBarItem(
                        selected = tab == it,
                        onClick = { tab = it },
                        icon = { Icon(it.icon, contentDescription = null) },
                        label = { Text(it.label) },
                    )
                }
            }
        },
    ) { padding ->
        AnimatedContent(
            tab,
            Modifier.padding(padding).consumeWindowInsets(padding),
            transitionSpec = { fadeIn(tween(200)) togetherWith fadeOut(tween(150)) },
            label = "tab",
        ) { shown ->
            when (shown) {
                Tab.Overview -> Refreshable(reload, dashboard) { Column(
                    Modifier
                        .fillMaxSize()
                        .verticalScroll(rememberScrollState())
                        .padding(16.dp),
                    verticalArrangement = Arrangement.spacedBy(16.dp),
                ) {
                    Text("Screen time", style = MaterialTheme.typography.headlineMedium)
                    if (!hasAccess) {
                        Card {
                            Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                                Text("This app needs usage access to see which apps you use.")
                                Button(onClick = {
                                    context.startActivity(Intent(AndroidSettings.ACTION_USAGE_ACCESS_SETTINGS))
                                }) { Text("Grant usage access") }
                            }
                        }
                    }
                    if (dashboard != null) {
                        Dashboard(dashboard, onOpenTimeline = { tab = Tab.Timeline })
                    } else {
                        if (hasAccess) UsageCard(refresh)
                        NoServerCard(onSettings = { tab = Tab.Settings })
                    }
                } }

                Tab.Timeline -> Refreshable(reload, dashboard) {
                    if (current != null && dashboard != null) {
                        TimelineScreen(dashboard)
                    } else {
                        Column(Modifier.padding(16.dp)) { NoServerCard(onSettings = { tab = Tab.Settings }) }
                    }
                }

                Tab.Settings -> SettingsScreen(
                    server = current,
                    lastSync = lastSync,
                    hasAccess = hasAccess,
                    onSave = { new ->
                        settings.server = new
                        server = new
                        Sync.schedule(context)
                    },
                    onRemove = {
                        settings.server = null
                        server = null
                        lastSync = null
                    },
                    onSynced = {
                        lastSync = settings.lastSync
                        refresh++
                    },
                    // the dashboard shows the new categories
                    onCategoriesChanged = { refresh++ },
                )
            }
        }
    }
}

/**
 * Pulling [content] down runs [onRefresh], the indicator stays until the
 * [dashboard] (if any) has loaded again.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun Refreshable(onRefresh: suspend () -> Unit, dashboard: DashboardState?, content: @Composable () -> Unit) {
    val scope = rememberCoroutineScope()
    var refreshing by remember { mutableStateOf(false) }
    PullToRefreshBox(
        isRefreshing = refreshing,
        onRefresh = {
            refreshing = true
            scope.launch {
                onRefresh()
                if (dashboard != null) {
                    // until the reload started and is done
                    withTimeoutOrNull(2_000) { snapshotFlow { dashboard.loading }.first { it } }
                    snapshotFlow { dashboard.loading }.first { !it }
                }
                refreshing = false
            }
        },
        modifier = Modifier.fillMaxSize(),
    ) { content() }
}

@Composable
private fun NoServerCard(onSettings: () -> Unit) {
    Card {
        Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
            Text("Add your server in the settings to see all your devices and the timeline.")
            Button(onClick = onSettings) { Text("Open settings") }
        }
    }
}

@Composable
private fun UsageCard(refresh: Int) {
    val context = LocalContext.current
    var data by remember { mutableStateOf<Pair<List<Pair<LocalDate, Long>>, List<Pair<String, Long>>>?>(null) }
    // not produceState, its lint check misfires with Kotlin 2.1
    LaunchedEffect(refresh) {
        data = withContext(Dispatchers.IO) {
            runCatching { Sync.collect(context) }
            Usage.dailyTotals(context, 7) to Usage.topAppsToday(context, 5)
        }
    }
    val (days, apps) = data ?: return

    Card {
        Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
            Text("Today", style = MaterialTheme.typography.labelLarge)
            Text(formatDuration(days.last().second), style = MaterialTheme.typography.displaySmall)
            WeekChart(days)
            apps.forEach { (app, ms) ->
                Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
                    Text(app, Modifier.weight(1f))
                    Text(formatDuration(ms))
                }
            }
        }
    }
}

@Composable
private fun WeekChart(days: List<Pair<LocalDate, Long>>) {
    val bar = MaterialTheme.colorScheme.primary
    val todayBar = MaterialTheme.colorScheme.tertiary
    val max = days.maxOf { it.second }.coerceAtLeast(1)
    Canvas(
        Modifier
            .fillMaxWidth()
            .height(120.dp)
    ) {
        val slot = size.width / days.size
        val width = slot * 0.6f
        days.forEachIndexed { i, (_, ms) ->
            val height = size.height * ms / max
            drawRoundRect(
                color = if (i == days.lastIndex) todayBar else bar,
                topLeft = Offset(i * slot + (slot - width) / 2, size.height - height),
                size = Size(width, height),
                cornerRadius = CornerRadius(4.dp.toPx()),
            )
        }
    }
    Row(Modifier.fillMaxWidth()) {
        days.forEach { (day, ms) ->
            Column(Modifier.weight(1f), horizontalAlignment = Alignment.CenterHorizontally) {
                Text(
                    day.dayOfWeek.getDisplayName(TextStyle.SHORT, Locale.getDefault()),
                    style = MaterialTheme.typography.labelSmall,
                )
                Text(
                    formatDuration(ms),
                    style = MaterialTheme.typography.labelSmall,
                    textAlign = TextAlign.Center,
                )
            }
        }
    }
}

fun formatDuration(ms: Long): String {
    val minutes = ms / 60_000
    return if (minutes < 60) "${minutes}m" else "${minutes / 60}h ${minutes % 60}m"
}
