package com.example.soko_langu

import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.Context
import android.content.Intent
import android.net.Uri
import androidx.media3.common.AudioAttributes
import androidx.media3.common.C
import androidx.media3.common.MediaItem
import androidx.media3.common.MediaMetadata
import androidx.media3.common.Player
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.session.MediaSession
import androidx.media3.session.MediaSessionService

class PlaybackService : MediaSessionService() {
    companion object {
        private var currentService: PlaybackService? = null
        var eventSink: ((Map<String, Any?>) -> Unit)? = null

        fun initPlaylist(songs: List<Map<String, Any?>>) {
            currentService?.internalInitPlaylist(songs)
        }
        fun playAtIndex(index: Int) {
            currentService?.internalPlayAtIndex(index)
        }
        fun play() {
            currentService?.let { svc ->
                svc.player?.playWhenReady = true
                svc.emitState()
            }
        }
        fun pause() {
            currentService?.let { svc ->
                svc.player?.playWhenReady = false
                svc.emitState()
            }
        }
        fun togglePlayPause() {
            currentService?.let { svc ->
                val p = svc.player ?: return@let
                p.playWhenReady = !p.playWhenReady
                svc.emitState()
            }
        }
        fun seekTo(positionMs: Long) {
            currentService?.player?.seekTo(positionMs)
        }
        fun next() {
            currentService?.player?.seekToNextMediaItem()
        }
        fun previous() {
            currentService?.player?.seekToPreviousMediaItem()
        }
        fun setRepeatMode(mode: Int) {
            currentService?.let { svc ->
                svc.player?.repeatMode = when (mode) {
                    1 -> Player.REPEAT_MODE_ONE
                    2 -> Player.REPEAT_MODE_ALL
                    else -> Player.REPEAT_MODE_OFF
                }
            }
        }
        fun setShuffle(enabled: Boolean) {
            currentService?.player?.shuffleModeEnabled = enabled
        }
        fun stop() {
            currentService?.let { svc ->
                svc.player?.stop()
                svc.player?.playWhenReady = false
                svc.emitState()
            }
        }
    }

    private var player: ExoPlayer? = null
    private var mediaSession: MediaSession? = null
    private var currentIndex: Int = -1

    override fun onCreate() {
        super.onCreate()
        currentService = this

        createNotificationChannel()

        @Suppress("DEPRECATION")
        val audioAttributes = AudioAttributes.Builder()
            .setContentType(C.CONTENT_TYPE_MUSIC)
            .setUsage(C.USAGE_MEDIA)
            .build()

        player = ExoPlayer.Builder(this)
            .setAudioAttributes(audioAttributes, true)
            .build()
            .also { p ->
                p.addListener(object : Player.Listener {
                    override fun onIsPlayingChanged(isPlaying: Boolean) {
                        emitState()
                    }
                    override fun onPlaybackStateChanged(state: Int) {
                        if (state == Player.STATE_ENDED) {
                            emitState()
                        }
                    }
                    override fun onMediaItemTransition(mediaItem: MediaItem?, reason: Int) {
                        if (mediaItem != null) {
                            currentIndex = mediaItem.mediaId.toIntOrNull() ?: -1
                        }
                        emitState()
                    }
                })
            }

        mediaSession = MediaSession.Builder(this, player!!).build()
    }

    private fun createNotificationChannel() {
        val channel = NotificationChannel(
            "media_session",
            "Soko Langu Player",
            NotificationManager.IMPORTANCE_LOW
        ).apply {
            description = "Media playback controls"
            setShowBadge(false)
        }
        val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        nm.createNotificationChannel(channel)
    }

    override fun onGetSession(controllerInfo: MediaSession.ControllerInfo): MediaSession? = mediaSession

    override fun onDestroy() {
        if (currentService === this) {
            currentService = null
        }
        mediaSession?.run {
            player?.release()
            release()
        }
        player = null
        mediaSession = null
        super.onDestroy()
    }

    override fun onTaskRemoved(rootIntent: Intent?) {
        val p = player
        if (p == null || (!p.playWhenReady && p.currentMediaItem == null)) {
            stopSelf()
        }
    }

    private fun internalInitPlaylist(songs: List<Map<String, Any?>>) {
        val p = player ?: return
        val mediaItems = songs.map { song ->
            val index = (song["index"] as? Int) ?: 0
            val filePath = song["filePath"] as? String ?: ""
            val title = song["title"] as? String ?: "Unknown"
            val artist = song["artist"] as? String ?: ""
            val durationMs = (song["durationMs"] as? Number)?.toLong() ?: 0L
            val artUriStr = song["artUri"] as? String

            val metadataBuilder = MediaMetadata.Builder()
                .setTitle(title)
                .setArtist(artist)
                .setDurationMs(durationMs)

            if (artUriStr != null && artUriStr.isNotEmpty()) {
                metadataBuilder.setArtworkUri(Uri.parse(artUriStr))
            }

            MediaItem.Builder()
                .setMediaId(index.toString())
                .setUri(filePath)
                .setMediaMetadata(metadataBuilder.build())
                .build()
        }
        p.setMediaItems(mediaItems)
    }

    private fun internalPlayAtIndex(index: Int) {
        val p = player ?: return
        if (index < 0 || index >= p.mediaItemCount) return
        p.seekToDefaultPosition(index)
        p.prepare()
        p.playWhenReady = true
        emitState()
    }

    private fun emitState() {
        val p = player ?: return
        val playing = p.playWhenReady && p.playbackState != Player.STATE_ENDED
        val state = mapOf<String, Any?>(
            "playing" to playing,
            "currentIndex" to currentIndex,
            "position" to p.currentPosition,
            "duration" to p.duration,
            "repeatMode" to p.repeatMode,
            "shuffle" to p.shuffleModeEnabled,
        )
        eventSink?.invoke(state)
    }
}
