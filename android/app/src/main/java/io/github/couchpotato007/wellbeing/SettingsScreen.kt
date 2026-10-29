package io.github.couchpotato007.wellbeing

import android.content.Intent
import android.os.Build
import android.provider.Settings as AndroidSettings
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.core.tween
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.slideInHorizontally
import androidx.compose.animation.slideOutHorizontally
import androidx.compose.foundation.layout.Box
import androidx.compose.material3.Surface
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.Card
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.text.input.VisualTransformation
import androidx.compose.ui.unit.dp
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.compose.LifecycleEventEffect
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

/** The server to sync with, syncing, usage access and the app version. */
@Composable
fun SettingsScreen(
    server: Server?,
    lastSync: String?,
    hasAccess: Boolean,
    onSave: (Server) -> Unit,
    onRemove: () -> Unit,
    onSynced: () -> Unit,
    onCategoriesChanged: () -> Unit,
) {
    var categories by rememberSaveable { mutableStateOf(false) }

    Box(Modifier.fillMaxSize()) {
        Column(
            Modifier
                .fillMaxSize()
                .verticalScroll(rememberScrollState())
                .imePadding()
                .padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(16.dp),
        ) {
            Text("Settings", style = MaterialTheme.typography.headlineMedium)
            ServerSettings(server, onSave)
            if (server != null) {
                SettingsCard("Categories") {
                    Text(
                        "Patterns that sort apps and websites into categories like Work > Programming, " +
                            "for all devices.",
                        style = MaterialTheme.typography.bodyMedium,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                    Button(onClick = { categories = true }) { Text("Manage categories") }
                }
                SyncSettings(server, lastSync, onSynced, onRemove)
            }
            AccessSettings(hasAccess)
            NotificationSettings()
            StoredSettings(lastSync)
            About()
        }

        // over the settings, the navigation bar stays
        AnimatedVisibility(
            categories && server != null,
            enter = slideInHorizontally(tween(300)) { it } + fadeIn(tween(300)),
            exit = slideOutHorizontally(tween(250)) { it } + fadeOut(tween(250)),
        ) {
            if (server != null) {
                Surface(Modifier.fillMaxSize()) {
                    CategoriesScreen(server, onBack = { categories = false }, onChanged = onCategoriesChanged)
                }
            }
        }
    }
}

/** Outcome of a connection test or save, shown under the buttons. */
private data class Status(val ok: Boolean, val text: String)

@Composable
private fun ServerSettings(server: Server?, onSave: (Server) -> Unit) {
    val scope = rememberCoroutineScope()
    var url by remember(server) { mutableStateOf(server?.url ?: "https://") }
    var token by remember(server) { mutableStateOf(server?.token.orEmpty()) }
    var device by remember(server) { mutableStateOf(server?.device ?: Build.MODEL) }
    var showToken by remember { mutableStateOf(false) }
    var testing by remember { mutableStateOf(false) }
    var status by remember { mutableStateOf<Status?>(null) }
    // a result is only about the values it was made with
    LaunchedEffect(url, token, device) { status = null }

    val entered = Server(url.trim(), token.trim(), device.trim())
    val valid = (entered.url.startsWith("https://") || entered.url.startsWith("http://")) &&
        entered.url.substringAfter("://").isNotEmpty() && entered.token.isNotEmpty() && entered.device.isNotEmpty()

    SettingsCard("Server") {
        Text(
            if (server == null) "Add your wellbeing server to sync this phone and see all your devices."
            else "Syncing as \"${server.device}\".",
            style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
        OutlinedTextField(
            url, { url = it },
            label = { Text("Server URL") },
            placeholder = { Text("https://wellbeing.example.org") },
            singleLine = true,
            keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Uri),
            modifier = Modifier.fillMaxWidth(),
        )
        OutlinedTextField(
            token, { token = it },
            label = { Text("Token") },
            supportingText = { Text("The server's ADMIN_TOKEN") },
            singleLine = true,
            visualTransformation = if (showToken) VisualTransformation.None else PasswordVisualTransformation(),
            keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Password),
            trailingIcon = {
                TextButton(onClick = { showToken = !showToken }) { Text(if (showToken) "Hide" else "Show") }
            },
            modifier = Modifier.fillMaxWidth(),
        )
        OutlinedTextField(
            device, { device = it },
            label = { Text("Device name") },
            supportingText = {
                Text(
                    if (server != null && entered.device != server.device) {
                        "A new name shows up as a new device on the server"
                    } else {
                        "How this phone is called on the dashboard"
                    }
                )
            },
            singleLine = true,
            modifier = Modifier.fillMaxWidth(),
        )
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
            OutlinedButton(
                enabled = valid && !testing,
                onClick = {
                    testing = true
                    scope.launch {
                        status = withContext(Dispatchers.IO) {
                            runCatching { Sync.test(entered) }
                                .fold({ Status(true, it) }, { Status(false, Sync.describe(it)) })
                        }
                        testing = false
                    }
                },
            ) { Text("Test connection") }
            Button(
                enabled = valid && entered != server,
                onClick = {
                    onSave(entered)
                    status = Status(true, "Saved. This phone syncs every 15 minutes.")
                },
            ) { Text(if (server == null) "Add server" else "Save") }
            if (testing) CircularProgressIndicator(Modifier.size(20.dp), strokeWidth = 2.dp)
        }
        AnimatedVisibility(status != null) {
            status?.let {
                Text(
                    (if (it.ok) "✓ " else "✗ ") + it.text,
                    style = MaterialTheme.typography.bodyMedium,
                    color = if (it.ok) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.error,
                )
            }
        }
    }
}

@Composable
private fun SyncSettings(server: Server, lastSync: String?, onSynced: () -> Unit, onRemove: () -> Unit) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    var syncing by remember { mutableStateOf(false) }
    var confirmRemove by remember { mutableStateOf(false) }

    SettingsCard("Sync") {
        Text(
            "Every 15 minutes when ${server.url} can be reached. Until then everything is kept on this phone.",
            style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
        Text("Last sync: " + (lastSync ?: "not yet"), style = MaterialTheme.typography.bodyMedium)
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
            OutlinedButton(
                onClick = { confirmRemove = true },
                colors = ButtonDefaults.outlinedButtonColors(contentColor = MaterialTheme.colorScheme.error),
            ) { Text("Remove server") }
        }
    }

    if (confirmRemove) {
        AlertDialog(
            onDismissRequest = { confirmRemove = false },
            title = { Text("Remove server?") },
            text = { Text("This phone stops syncing and forgets the server. What the server already has stays there.") },
            confirmButton = {
                TextButton(onClick = {
                    confirmRemove = false
                    onRemove()
                }) { Text("Remove") }
            },
            dismissButton = { TextButton(onClick = { confirmRemove = false }) { Text("Cancel") } },
        )
    }
}

@Composable
private fun AccessSettings(hasAccess: Boolean) {
    val context = LocalContext.current
    SettingsCard("Usage access") {
        Text(
            if (hasAccess) "✓ Granted, the app can read which apps you use."
            else "Not granted. Without it this phone's screen time can't be synced.",
            style = MaterialTheme.typography.bodyMedium,
            color = if (hasAccess) MaterialTheme.colorScheme.onSurfaceVariant else MaterialTheme.colorScheme.error,
        )
        OutlinedButton(onClick = { context.startActivity(Intent(AndroidSettings.ACTION_USAGE_ACCESS_SETTINGS)) }) {
            Text(if (hasAccess) "Open usage access settings" else "Grant usage access")
        }
    }
}

@Composable
private fun NotificationSettings() {
    val context = LocalContext.current
    var granted by remember { mutableStateOf(Listener.hasAccess(context)) }
    LifecycleEventEffect(Lifecycle.Event.ON_RESUME) { granted = Listener.hasAccess(context) }
    SettingsCard("Notification access") {
        Text(
            if (granted) "✓ Granted, the app counts notifications per app and records when media plays."
            else "Optional. Lets the app count notifications per app (not what they say) and record " +
                "when music, podcasts or videos play.",
            style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
        OutlinedButton(onClick = {
            // straight to this app's switch (Android 11+), otherwise the list of all apps
            val list = Intent(AndroidSettings.ACTION_NOTIFICATION_LISTENER_SETTINGS)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                val detail = Intent(AndroidSettings.ACTION_NOTIFICATION_LISTENER_DETAIL_SETTINGS).putExtra(
                    AndroidSettings.EXTRA_NOTIFICATION_LISTENER_COMPONENT_NAME,
                    android.content.ComponentName(context, Listener::class.java).flattenToString(),
                )
                runCatching { context.startActivity(detail) }.onFailure { context.startActivity(list) }
            } else {
                context.startActivity(list)
            }
        }) {
            Text(if (granted) "Open notification access settings" else "Grant notification access")
        }
    }
}

/** What this phone keeps, and what the server doesn't have yet. */
@Composable
private fun StoredSettings(lastSync: String?) {
    val context = LocalContext.current
    var text by remember { mutableStateOf<String?>(null) }
    LaunchedEffect(lastSync) {
        text = withContext(Dispatchers.IO) {
            val store = Store.get(context)
            val (count, oldest) = store.summary()
            val format = java.text.DateFormat.getDateTimeInstance(java.text.DateFormat.MEDIUM, java.text.DateFormat.SHORT)
            val since = oldest?.let { " since " + java.text.DateFormat.getDateInstance().format(java.util.Date(it)) }
            val pending = store.getState("pending_from_ms")
            "$count events${since.orEmpty()}, kept for ${Store.KEEP_DAYS} days. " +
                if (pending == null) "All uploaded." else "Not uploaded from ${format.format(java.util.Date(pending))} on."
        }
    }
    SettingsCard("On this phone") {
        Text(text ?: "…", style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
    }
}

@Composable
private fun About() {
    val context = LocalContext.current
    val version = remember {
        runCatching { context.packageManager.getPackageInfo(context.packageName, 0).versionName }.getOrNull()
    }
    Text(
        "Wellbeing ${version.orEmpty()} · Android ${Build.VERSION.RELEASE}",
        style = MaterialTheme.typography.bodySmall,
        color = MaterialTheme.colorScheme.onSurfaceVariant,
        modifier = Modifier.padding(horizontal = 4.dp),
    )
}

@Composable
private fun SettingsCard(title: String, content: @Composable () -> Unit) {
    Card {
        Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
            Text(title, style = MaterialTheme.typography.titleMedium)
            content()
        }
    }
}
