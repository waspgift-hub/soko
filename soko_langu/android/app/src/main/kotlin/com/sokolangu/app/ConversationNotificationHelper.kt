package com.sokolangu.app

import android.app.Notification
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.Build
import androidx.core.app.NotificationCompat
import androidx.core.app.Person
import androidx.core.content.pm.ShortcutInfoCompat
import androidx.core.content.pm.ShortcutManagerCompat

object ConversationNotificationHelper {
    private const val CHANNEL_ID = "chat_messages_v6"
    private const val TAG = "chat_conv"

    fun show(context: Context, senderName: String, messageText: String, roomId: String, senderId: String) {
        val notificationId = (roomId.hashCode() and Int.MAX_VALUE).coerceAtLeast(1)
        val sender = Person.Builder()
            .setName(senderName)
            .setKey(senderId.ifEmpty { senderName })
            .build()

        val style = NotificationCompat.MessagingStyle(sender)
            .addMessage(messageText, System.currentTimeMillis(), sender)

        val intent = context.packageManager.getLaunchIntentForPackage(context.packageName) ?: return
        intent.flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
        if (roomId.isNotEmpty()) {
            intent.putExtra("route", "/chat/$roomId")
        }

        val flags = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        } else {
            PendingIntent.FLAG_UPDATE_CURRENT
        }
        val pendingIntent = PendingIntent.getActivity(context, notificationId, intent, flags)

        // Push dynamic shortcut for conversation section placement
        if (roomId.isNotEmpty()) {
            val shortcutIntent = Intent(context, MainActivity::class.java).apply {
                action = Intent.ACTION_VIEW
                putExtra("route", "/chat/$roomId")
            }
            val shortcut = ShortcutInfoCompat.Builder(context, "chat_$roomId")
                .setShortLabel(senderName.take(10))
                .setLongLabel("Chat with $senderName")
                .setIntent(shortcutIntent)
                .setLongLived(true)
                .setPerson(sender)
                .setIsConversation()
                .build()
            try { ShortcutManagerCompat.pushDynamicShortcut(context, shortcut) } catch (_: Exception) {}
        }

        val notification = NotificationCompat.Builder(context, CHANNEL_ID)
            .setSmallIcon(android.R.drawable.ic_dialog_email)
            .setStyle(style)
            .setContentIntent(pendingIntent)
            .setAutoCancel(true)
            .setCategory(NotificationCompat.CATEGORY_MESSAGE)
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .setDefaults(Notification.DEFAULT_ALL)
            .setGroup("chat_messages_v6")
            .setGroupSummary(false)
            .setSortKey(roomId)
            .apply {
                if (roomId.isNotEmpty()) setShortcutId("chat_$roomId")
            }
            .build()

        val manager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        manager.notify(TAG, notificationId, notification)
    }
}
