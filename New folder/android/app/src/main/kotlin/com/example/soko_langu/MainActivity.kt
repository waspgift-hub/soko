package com.example.soko_langu

import android.content.ContentUris
import android.os.Build
import android.provider.MediaStore
import android.util.Log
import com.ryanheise.audioservice.AudioServiceActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : AudioServiceActivity() {
    private val VIDEO_CHANNEL = "soko_lang/video_query"
    private val DEVICE_CHANNEL = "soko_lang/device_info"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            VIDEO_CHANNEL,
        ).setMethodCallHandler { call, result ->
            if (call.method == "queryVideos") {
                result.success(queryVideos())
            } else {
                result.notImplemented()
            }
        }

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            DEVICE_CHANNEL,
        ).setMethodCallHandler { call, result ->
            if (call.method == "getSdkVersion") {
                result.success(Build.VERSION.SDK_INT)
            } else {
                result.notImplemented()
            }
        }
    }

    private fun queryVideos(): List<Map<String, Any?>> {
        val videos = mutableListOf<Map<String, Any?>>()
        try {
            val uri = MediaStore.Video.Media.EXTERNAL_CONTENT_URI
            val projection = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                arrayOf(
                    MediaStore.Video.Media._ID,
                    MediaStore.Video.Media.DISPLAY_NAME,
                    MediaStore.Video.Media.DURATION,
                    MediaStore.Video.Media.SIZE,
                    MediaStore.Video.Media.WIDTH,
                    MediaStore.Video.Media.HEIGHT,
                    MediaStore.Video.Media.RELATIVE_PATH,
                )
            } else {
                arrayOf(
                    MediaStore.Video.Media._ID,
                    MediaStore.Video.Media.DATA,
                    MediaStore.Video.Media.DISPLAY_NAME,
                    MediaStore.Video.Media.DURATION,
                    MediaStore.Video.Media.SIZE,
                )
            }

            val selection = "${MediaStore.Video.Media.DURATION} > 0"
            val sortOrder = "${MediaStore.Video.Media.DATE_ADDED} DESC"

            val cursor = contentResolver.query(uri, projection, selection, null, sortOrder)
            cursor?.use {
                val idCol = it.getColumnIndexOrThrow(MediaStore.Video.Media._ID)
                val nameCol = it.getColumnIndexOrThrow(MediaStore.Video.Media.DISPLAY_NAME)
                val durCol = it.getColumnIndexOrThrow(MediaStore.Video.Media.DURATION)
                val sizeCol = it.getColumnIndexOrThrow(MediaStore.Video.Media.SIZE)

                while (it.moveToNext()) {
                    val videoId = it.getLong(idCol)
                    var dataPath = ""
                    if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) {
                        try {
                            val dataCol = it.getColumnIndexOrThrow(MediaStore.Video.Media.DATA)
                            dataPath = it.getString(dataCol) ?: ""
                        } catch (_: Exception) {}
                    }
                    val contentUri = ContentUris.withAppendedId(
                        MediaStore.Video.Media.EXTERNAL_CONTENT_URI,
                        videoId,
                    ).toString()

                    videos.add(
                        mapOf<String, Any?>(
                            "displayName" to (it.getString(nameCol) ?: "Unknown"),
                            "id" to videoId,
                            "duration" to it.getLong(durCol),
                            "size" to it.getLong(sizeCol),
                            "data" to dataPath,
                            "contentUri" to contentUri,
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
