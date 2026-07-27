package com.sokolangu.app

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.Context
import android.content.Intent
import android.os.Build
import android.widget.RemoteViews

class SokoVibeWidgetProvider : AppWidgetProvider() {

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray
    ) {
        val data = WidgetDataStore.load(context)
        for (appWidgetId in appWidgetIds) {
            updateAppWidget(context, appWidgetManager, appWidgetId, data)
        }
    }

    override fun onEnabled(context: Context) {
        // Widget added to home screen
    }

    override fun onDisabled(context: Context) {
        // Last widget removed
    }

    companion object {
        fun updateAppWidget(
            context: Context,
            appWidgetManager: AppWidgetManager,
            appWidgetId: Int,
            data: WidgetDataStore.WidgetData
        ) {
            val views = RemoteViews(context.packageName, R.layout.widget_soko_vibe)

            views.setTextViewText(R.id.widget_value_sales, data.sales)
            views.setTextViewText(R.id.widget_value_orders, data.orders)
            views.setTextViewText(R.id.widget_value_balance, data.balance)

            val pendingFlags = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            } else {
                PendingIntent.FLAG_UPDATE_CURRENT
            }

            val chatIntent = Intent(context, MainActivity::class.java).apply {
                putExtra("route", "/chat")
                this.flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
            }
            views.setOnClickPendingIntent(
                R.id.widget_action_chat,
                PendingIntent.getActivity(context, 1001, chatIntent, pendingFlags)
            )

            val ordersIntent = Intent(context, MainActivity::class.java).apply {
                putExtra("route", "/seller-orders")
                this.flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
            }
            views.setOnClickPendingIntent(
                R.id.widget_action_orders,
                PendingIntent.getActivity(context, 1002, ordersIntent, pendingFlags)
            )

            val boostIntent = Intent(context, MainActivity::class.java).apply {
                putExtra("route", "/boost-product")
                this.flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
            }
            views.setOnClickPendingIntent(
                R.id.widget_action_boost,
                PendingIntent.getActivity(context, 1003, boostIntent, pendingFlags)
            )

            appWidgetManager.updateAppWidget(appWidgetId, views)
        }
    }
}
