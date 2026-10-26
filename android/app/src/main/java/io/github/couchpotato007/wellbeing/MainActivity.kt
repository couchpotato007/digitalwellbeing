package io.github.couchpotato007.wellbeing

import android.content.Intent
import android.os.Build
import android.os.Bundle
import android.provider.Settings as AndroidSettings
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeDrawingPadding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
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
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.compose.LifecycleEventEffect
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
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

@Composable
private fun App() {
    val context = LocalContext.current
    val settings = remember { Settings(context) }
    var hasAccess by remember { mutableStateOf(Usage.hasAccess(context)) }
    var server by remember { mutableStateOf(settings.server) }
    var lastSync by remember { mutableStateOf(settings.lastSync) }
    // bumped to reload the chart and status
    var refresh by remember { mutableIntStateOf(0) }

    LifecycleEventEffect(Lifecycle.Event.ON_RESUME) {
        hasAccess = Usage.hasAccess(context)
        lastSync = settings.lastSync
        refresh++
    }

    Column(
        Modifier
            .safeDrawingPadding()
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

        val current = server
        // with a server, all devices from there, otherwise only this phone
        if (current != null) Dashboard(current, refresh)
        else if (hasAccess) UsageCard(refresh)

        if (current == null) {
            ServerForm(onSave = { new ->
                settings.server = new
                server = new
                Sync.schedule(context)
            })
        } else {
            ServerCard(
                server = current,
                lastSync = lastSync,
                onSynced = {
                    lastSync = settings.lastSync
                    refresh++
                },
                onRemove = {
                    Sync.cancel(context)
                    settings.server = null
                    server = null
                    lastSync = null
                },
            )
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

@Composable
private fun ServerForm(onSave: (Server) -> Unit) {
    var url by remember { mutableStateOf("https://") }
    var token by remember { mutableStateOf("") }
    var device by remember { mutableStateOf(Build.MODEL) }

    Card {
        Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
            Text("Add server", style = MaterialTheme.typography.titleMedium)
            OutlinedTextField(
                url, { url = it },
                label = { Text("Server URL") },
                singleLine = true,
                keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Uri),
                modifier = Modifier.fillMaxWidth(),
            )
            OutlinedTextField(
                token, { token = it },
                label = { Text("Token (ADMIN_TOKEN)") },
                singleLine = true,
                visualTransformation = PasswordVisualTransformation(),
                keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Password),
                modifier = Modifier.fillMaxWidth(),
            )
            OutlinedTextField(
                device, { device = it },
                label = { Text("Device name") },
                singleLine = true,
                modifier = Modifier.fillMaxWidth(),
            )
            Button(
                enabled = url.trim().length > "https://".length && token.isNotBlank() && device.isNotBlank(),
                onClick = { onSave(Server(url.trim(), token.trim(), device.trim())) },
            ) { Text("Save") }
        }
    }
}

@Composable
private fun ServerCard(server: Server, lastSync: String?, onSynced: () -> Unit, onRemove: () -> Unit) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    var syncing by remember { mutableStateOf(false) }

    Card {
        Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
            Text("Server", style = MaterialTheme.typography.titleMedium)
            Text(server.url)
            Text("as \"${server.device}\", every 15 min", style = MaterialTheme.typography.bodySmall)
            Text(lastSync ?: "Not synced yet", style = MaterialTheme.typography.bodySmall)
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                Button(
                    enabled = !syncing,
                    onClick = {
                        syncing = true
                        scope.launch {
                            withContext(Dispatchers.IO) { runCatching { Sync.run(context) } }
                            syncing = false
                            onSynced()
                        }
                    },
                ) { Text(if (syncing) "Syncing…" else "Sync now") }
                OutlinedButton(onClick = onRemove) { Text("Remove") }
            }
        }
    }
}

fun formatDuration(ms: Long): String {
    val minutes = ms / 60_000
    return if (minutes < 60) "${minutes}m" else "${minutes / 60}h ${minutes % 60}m"
}
