package com.sokolangu.app

import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.ContentUris
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.drawable.Icon
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.provider.MediaStore
import android.appwidget.AppWidgetManager
import android.util.Log
import androidx.core.content.ContextCompat
import com.ryanheise.audioservice.AudioServiceActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

// AudioServiceActivity keeps the FlutterActivity lineage (it subclasses it) and
// adds the media-button receiver wiring audio_service needs. FragmentActivity
// would break the Flutter embedding, so it is deliberately not used here.
class MainActivity : AudioServiceActivity() {
    private val CHANNEL = "soko_lang/video_query"
    private var pendingRoute: String? = null
    private var initialSharePaths: List<String>? = null
    private var shareEventSink: EventChannel.EventSink? = null
    private var pendingSharePaths: List<String>? = null
    // Share intent still copying to cache in background; getInitialMedia waits on it
    private var pendingShareIntent: Intent? = null
    private val initialShareWaiters = mutableListOf<MethodChannel.Result>()

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        createNotificationChannels()
        pendingRoute = intent?.getStringExtra("route")
        // Capture Gallery share that launched the app — copy to cache async so a
        // large video can't ANR the main thread at cold start
        scheduleShareExtraction(intent)
    }

    override fun onNewIntent(intent: android.content.Intent) {
        super.onNewIntent(intent)
        // Chat shortcut route
        intent.getStringExtra("route")?.let { route ->
            flutterEngine?.dartExecutor?.binaryMessenger?.let { messenger ->
                MethodChannel(messenger, "soko_lang/navigate").invokeMethod("navigate", route)
            }
        }
        // Gallery share while app is alive — copied off the main thread, delivered
        // via EventChannel once ready (or held if the stream isn't listening yet).
        scheduleShareExtraction(intent)
        // App Links / deep link data is handled separately via the app_links plugin
    }

    private fun scheduleShareExtraction(intent: Intent?) {
        if (intent == null || pendingShareIntent != null) return
        pendingShareIntent = intent
        Thread {
            val paths = try { extractSharePaths(intent) } catch (e: Exception) { null }
            Handler(Looper.getMainLooper()).post {
                pendingShareIntent = null
                deliverSharePaths(paths)
            }
        }.start()
    }

    private fun deliverSharePaths(paths: List<String>?) {
        val result = paths?.takeIf { it.isNotEmpty() }
        if (initialShareWaiters.isNotEmpty()) {
            // Cold start — Dart is still awaiting getInitialMedia
            initialSharePaths = result
            for (w in initialShareWaiters) w.success(result)
            initialShareWaiters.clear()
            return
        }
        // Warm start — push via the open stream, else hold and nudge Dart
        val sink = shareEventSink
        if (sink != null && result != null && result.isNotEmpty()) {
            sink.success(result)
            pendingSharePaths = null
        } else {
            pendingSharePaths = result
            if (result != null && result.isNotEmpty()) {
                flutterEngine?.dartExecutor?.binaryMessenger?.let { messenger ->
                    MethodChannel(messenger, "soko/share_receive").invokeMethod("onMediaShared", result)
                }
            }
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            CHANNEL,
        ).setMethodCallHandler { call, result ->
            if (call.method == "queryVideos") {
                result.success(queryVideos())
            } else {
                result.notImplemented()
            }
        }
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "soko_lang/conversation_notif",
        ).setMethodCallHandler { call, result ->
            if (call.method == "show") {
                val senderName = call.argument<String>("senderName") ?: "Mtumiaji"
                val messageText = call.argument<String>("messageText") ?: ""
                val roomId = call.argument<String>("roomId") ?: ""
                val senderId = call.argument<String>("senderId") ?: ""
                ConversationNotificationHelper.show(this, senderName, messageText, roomId, senderId)
                result.success(true)
            } else {
                result.notImplemented()
            }
        }
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "soko_lang/widget",
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "updateWidget" -> {
                    val sales = call.argument<String>("sales") ?: "TZS 0"
                    val orders = call.argument<String>("orders") ?: "0"
                    val balance = call.argument<String>("balance") ?: "TZS 0"
                    WidgetDataStore.save(this, sales, orders, balance)
                    val manager = AppWidgetManager.getInstance(this)
                    val ids = manager.getAppWidgetIds(
                        android.content.ComponentName(this, SokoVibeWidgetProvider::class.java)
                    )
                    val data = WidgetDataStore.load(this)
                    ids.forEach { id ->
                        SokoVibeWidgetProvider.updateAppWidget(this, manager, id, data)
                    }
                    result.success(true)
                }
                "updateFlashSales" -> {
                    // hw: persist a local copy in case Dart prefs aren't flushed yet
                    val trending = call.argument<String>("trendingJson") ?: ""
                    if (trending.isNotEmpty()) WidgetDataStore.saveTrendingJson(this, trending)
                    val manager = AppWidgetManager.getInstance(this)
                    val ids = manager.getAppWidgetIds(
                        android.content.ComponentName(this, FlashSalesWidgetProvider::class.java)
                    )
                    ids.forEach { id ->
                        FlashSalesWidgetProvider.updateAppWidget(this, manager, id)
                    }
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        }
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "soko_lang/shortcut",
        ).setMethodCallHandler { call, result ->
            if (call.method == "pinShortcut") {
                val receiverId = call.argument<String>("receiverId") ?: ""
                val receiverName = call.argument<String>("receiverName") ?: "Chat"
                val success = pinShortcutToHomeScreen(receiverId, receiverName)
                result.success(success)
            } else {
                result.notImplemented()
            }
        }
        // Share receive channels — gallery → Soko Vibe
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "soko/share_receive").setMethodCallHandler { call, result ->
            if (call.method == "getInitialMedia") {
                if (initialSharePaths != null) {
                    result.success(initialSharePaths)
                    pendingSharePaths = initialSharePaths
                    initialSharePaths = null
                } else if (pendingShareIntent != null) {
                    // background copy still in flight — answer when it finishes
                    initialShareWaiters.add(result)
                } else {
                    result.success(null)
                }
            } else if (call.method == "clearPending") {
                pendingSharePaths = null
                result.success(true)
            } else {
                result.notImplemented()
            }
        }
        EventChannel(flutterEngine.dartExecutor.binaryMessenger, "soko/share_receive_stream").setStreamHandler(
            object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    shareEventSink = events
                    pendingSharePaths?.let { paths ->
                        events?.success(paths)
                        pendingSharePaths = null
                    }
                }
                override fun onCancel(arguments: Any?) {
                    shareEventSink = null
                }
            }
        )
        handleIntent(intent)
        pendingRoute?.let { route ->
            MethodChannel(
                flutterEngine.dartExecutor.binaryMessenger,
                "soko_lang/navigate",
            ).invokeMethod("navigate", route)
            pendingRoute = null
        }
    }

    private fun handleIntent(intent: Intent?) {
        val uri = intent?.data ?: return
        if (uri.scheme == "shortcut_soko_vibe" && uri.host == "chat") {
            val receiverId = uri.lastPathSegment ?: return
            val receiverName = uri.getQueryParameter("name") ?: ""
            pendingRoute = "/chat/$receiverId"
        }
    }

    private fun extractSharePaths(intent: Intent?): List<String>? {
        if (intent == null) return null
        val action = intent.action
        if (action != Intent.ACTION_SEND && action != Intent.ACTION_SEND_MULTIPLE) return null
        val type = intent.type ?: ""
        // Accept image/*, video/* and mixed *.*
        if (!type.startsWith("image/") && !type.startsWith("video/") && type != "*/*" && !type.startsWith("application/")) {
            // Still allow if extras contain streams — some galleries send text/* with images
            if (intent.getParcelableExtra<android.os.Parcelable>(Intent.EXTRA_STREAM) == null &&
                intent.getParcelableArrayListExtra<android.os.Parcelable>(Intent.EXTRA_STREAM) == null) return null
        }
        val out = mutableListOf<String>()
        try {
            if (action == Intent.ACTION_SEND) {
                val uri = intent.getParcelableExtra<android.net.Uri>(Intent.EXTRA_STREAM) ?: return null
                copyUriToCache(uri)?.let { out.add(it) }
            } else {
                val uris = intent.getParcelableArrayListExtra<android.net.Uri>(Intent.EXTRA_STREAM) ?: return null
                for (uri in uris) {
                    if (out.size >= 5) break
                    copyUriToCache(uri)?.let { out.add(it) }
                }
            }
        } catch (e: Exception) {
            Log.e("ShareReceive", "extractSharePaths failed: ${e.message}", e)
        }
        if (out.isEmpty()) return null
        Log.d("ShareReceive", "extracted ${out.size} share paths")
        return out
    }

    private fun copyUriToCache(uri: android.net.Uri): String? {
        return try {
            val resolver = contentResolver
            val mime = resolver.getType(uri) ?: ""
            // Validate MIME — only image/video allowed
            if (!mime.startsWith("image/") && !mime.startsWith("video/") && mime != "application/octet-stream") {
                // Some file managers send empty mime — allow but validate extension later in Dart
            }
            val input = resolver.openInputStream(uri) ?: return null
            // Determine extension from mime or uri
            val ext = when {
                mime == "image/jpeg" -> "jpg"
                mime == "image/png" -> "png"
                mime == "image/webp" -> "webp"
                mime == "image/heic" -> "heic"
                mime == "video/mp4" -> "mp4"
                mime == "video/quicktime" -> "mov"
                mime == "video/3gpp" -> "3gp"
                else -> {
                    val name = uri.lastPathSegment ?: ""
                    val dot = name.lastIndexOf('.')
                    if (dot >= 0 && dot < name.length - 1) name.substring(dot + 1).lowercase() else "tmp"
                }
            }
            val isVideo = mime.startsWith("video/")
            val prefix = if (isVideo) "share_vid_" else "share_img_"
            val cacheFile = java.io.File.createTempFile(prefix, ".$ext", cacheDir)
            input.use { ins ->
                cacheFile.outputStream().use { out -> ins.copyTo(out) }
            }
            // Size guard: 100MB video, 20MB image
            val max = if (isVideo) 100L * 1024 * 1024 else 20L * 1024 * 1024
            if (cacheFile.length() > max) {
                cacheFile.delete()
                return null
            }
            if (cacheFile.length() == 0L) {
                cacheFile.delete()
                return null
            }
            cacheFile.absolutePath
        } catch (e: Exception) {
            Log.e("ShareReceive", "copyUriToCache failed for $uri: ${e.message}", e)
            null
        }
    }

    private fun pinShortcutToHomeScreen(receiverId: String, receiverName: String): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return false
        return try {
            val shortcutManager = getSystemService(android.content.pm.ShortcutManager::class.java)
            if (!shortcutManager.isRequestPinShortcutSupported) return false
            val intent = Intent(this, MainActivity::class.java).apply {
                action = Intent.ACTION_VIEW
                data = android.net.Uri.parse("shortcut_soko_vibe://chat/$receiverId?name=${android.net.Uri.encode(receiverName)}")
                putExtra("route", "/chat/$receiverId")
                flags = Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP
            }
            val appIcon = ContextCompat.getDrawable(this, R.mipmap.ic_launcher)
            val bitmap = Bitmap.createBitmap(108, 108, Bitmap.Config.ARGB_8888).also { bmp ->
                val canvas = Canvas(bmp)
                appIcon?.setBounds(0, 0, 108, 108)
                appIcon?.draw(canvas)
            }
            val shortcut = android.content.pm.ShortcutInfo.Builder(this, "chat_$receiverId")
                .setShortLabel(receiverName.take(10))
                .setLongLabel(receiverName.take(25))
                .setIcon(Icon.createWithBitmap(bitmap))
                .setIntent(intent)
                .build()
            shortcutManager.requestPinShortcut(shortcut, null)
            true
        } catch (e: Exception) {
            Log.e("Shortcut", "Failed to pin shortcut: ${e.message}", e)
            false
        }
    }

    private fun createNotificationChannels() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val manager = getSystemService(NotificationManager::class.java)
            // Delete old v4/v5 channels (can't modify once created — need new IDs for IMPORTANCE_MAX)
            listOf("onesignal_default_channel","general_notifications_v4","chat_messages_v4","payments_notifications_v4","general_notifications_v5","chat_messages_v5","payments_notifications_v5","system_alerts_v5","ride_notifications_v5").forEach {
                try { manager.deleteNotificationChannel(it) } catch (_: Exception) {}
            }
            // Recreate OneSignal default channel with MAX importance for instant display
            manager.createNotificationChannel(
                NotificationChannel(
                    "onesignal_default_channel",
                    "Notifications",
                    NotificationManager.IMPORTANCE_MAX
                ).apply {
                    description = "Soko Vibe notifications — urgent"
                    enableVibration(true)
                    enableLights(true)
                    setSound(
                        android.net.Uri.parse("android.resource://$packageName/${R.raw.soko_notification}"),
                        android.app.Notification.AUDIO_ATTRIBUTES_DEFAULT
                    )
                }
            )
            val channels = listOf(
                NotificationChannel(
                    "general_notifications_v6",
                    "Soko Vibe",
                    NotificationManager.IMPORTANCE_MAX
                ).apply {
                    description = "Flash sale, announcements, alerts"
                    enableVibration(true)
                    enableLights(true)
                    setShowBadge(true)
                    setSound(
                        android.net.Uri.parse("android.resource://$packageName/${R.raw.soko_notification}"),
                        android.app.Notification.AUDIO_ATTRIBUTES_DEFAULT
                    )
                },
                NotificationChannel(
                    "payments_notifications_v6",
                    "Payments",
                    NotificationManager.IMPORTANCE_MAX
                ).apply {
                    description = "Malipo, escrow, payout, refund notifications"
                    enableVibration(true)
                    enableLights(true)
                    setShowBadge(true)
                    setSound(
                        android.net.Uri.parse("android.resource://$packageName/${R.raw.soko_notification}"),
                        android.app.Notification.AUDIO_ATTRIBUTES_DEFAULT
                    )
                },
                NotificationChannel(
                    "chat_messages_v6",
                    "Chat Messages",
                    NotificationManager.IMPORTANCE_MAX
                ).apply {
                    description = "New message notifications from chats"
                    enableVibration(true)
                    enableLights(true)
                    setShowBadge(true)
                    setSound(
                        android.net.Uri.parse("android.resource://$packageName/${R.raw.soko_notification}"),
                        android.app.Notification.AUDIO_ATTRIBUTES_DEFAULT
                    )
                },
                NotificationChannel(
                    "system_alerts_v6",
                    "System Alerts",
                    NotificationManager.IMPORTANCE_MAX
                ).apply {
                    description = "Account security, suspension, verification alerts"
                    enableVibration(true)
                    enableLights(true)
                    setShowBadge(true)
                    setSound(
                        android.net.Uri.parse("android.resource://$packageName/${R.raw.soko_notification}"),
                        android.app.Notification.AUDIO_ATTRIBUTES_DEFAULT
                    )
                },
                NotificationChannel(
                    "ride_notifications_v6",
                    "Ride Updates",
                    NotificationManager.IMPORTANCE_MAX
                ).apply {
                    description = "Ride requests, cancellations, trip updates"
                    enableVibration(true)
                    enableLights(true)
                    setShowBadge(true)
                    setSound(
                        android.net.Uri.parse("android.resource://$packageName/${R.raw.soko_notification}"),
                        android.app.Notification.AUDIO_ATTRIBUTES_DEFAULT
                    )
                }
            )
            channels.forEach { manager.createNotificationChannel(it) }
            // Android 13+ inline replies use the system notification assistant by default
        }
    }

    private fun queryVideos(): List<Map<String, Any?>> {
        val videos = mutableListOf<Map<String, Any?>>()
        try {
            val uri = MediaStore.Video.Media.EXTERNAL_CONTENT_URI
            val projection = arrayOf(
                MediaStore.Video.Media._ID,
                MediaStore.Video.Media.DATA,
                MediaStore.Video.Media.DISPLAY_NAME,
                MediaStore.Video.Media.DURATION,
                MediaStore.Video.Media.SIZE,
            )
            val cursor = contentResolver.query(uri, projection, null, null, null)
            cursor?.use {
                val idCol = it.getColumnIndexOrThrow(MediaStore.Video.Media._ID)
                val nameCol = it.getColumnIndexOrThrow(MediaStore.Video.Media.DISPLAY_NAME)
                val durCol = it.getColumnIndexOrThrow(MediaStore.Video.Media.DURATION)
                val sizeCol = it.getColumnIndexOrThrow(MediaStore.Video.Media.SIZE)

                while (it.moveToNext()) {
                    val videoId = it.getLong(idCol)
                    var dataPath: String? = null
                    try {
                        val dataCol = it.getColumnIndexOrThrow(MediaStore.Video.Media.DATA)
                        dataPath = it.getString(dataCol)
                    } catch (_: Exception) {}
                    videos.add(
                        mapOf<String, Any?>(
                            "displayName" to (it.getString(nameCol) ?: "Unknown"),
                            "id" to videoId,
                            "duration" to it.getLong(durCol),
                            "size" to it.getLong(sizeCol),
                            "data" to (dataPath ?: ""),
                            "contentUri" to ContentUris.withAppendedId(
                                MediaStore.Video.Media.EXTERNAL_CONTENT_URI,
                                videoId,
                            ).toString(),
                        ),
                    )
                }
            }
            Log.d("VideoQuery", "Found ${videos.size} videos")
        } catch (e: Exception) {
            Log.e("VideoQuery", "Error querying videos: ${e.message}", e)
        }
        return videos
    }
}
