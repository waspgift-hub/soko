package com.sokolangu.app

import android.content.Context
import android.content.SharedPreferences

object WidgetDataStore {
    private const val PREFS_NAME = "soko_vibe_widget_data"
    private const val FLUTTER_PREFS_NAME = "FlutterSharedPreferences"
    private const val KEY_SALES = "widget_sales"
    private const val KEY_ORDERS = "widget_orders"
    private const val KEY_BALANCE = "widget_balance"
    private const val KEY_TIMESTAMP = "widget_timestamp"
    // Written by Dart shared_preferences (prefixed with "flutter.") — see WidgetService
    private const val KEY_TRENDING = "flutter.trending_products_data"
    // Local fallback written through the native channel
    private const val KEY_TRENDING_LOCAL = "trending_products_data"

    data class WidgetData(
        val sales: String = "TZS 0",
        val orders: String = "0",
        val balance: String = "TZS 0",
        val timestamp: Long = 0L
    )

    private fun prefs(context: Context): SharedPreferences =
        context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)

    fun save(context: Context, sales: String, orders: String, balance: String) {
        prefs(context).edit()
            .putString(KEY_SALES, sales)
            .putString(KEY_ORDERS, orders)
            .putString(KEY_BALANCE, balance)
            .putLong(KEY_TIMESTAMP, System.currentTimeMillis())
            .apply()
    }

    fun load(context: Context): WidgetData {
        val p = prefs(context)
        return WidgetData(
            sales = p.getString(KEY_SALES, "TZS 0") ?: "TZS 0",
            orders = p.getString(KEY_ORDERS, "0") ?: "0",
            balance = p.getString(KEY_BALANCE, "TZS 0") ?: "TZS 0",
            timestamp = p.getLong(KEY_TIMESTAMP, 0L)
        )
    }

    /// JSON array of trending/flash-sale products for the home widget.
    ///
    /// Prefers the value written by Dart shared_preferences so the widget and the
    /// app stay in sync; falls back to the native channel value.
    fun loadTrendingJson(context: Context): String? {
        val flutterPrefs = context.getSharedPreferences(FLUTTER_PREFS_NAME, Context.MODE_PRIVATE)
        return flutterPrefs.getString(KEY_TRENDING, null)
            ?: prefs(context).getString(KEY_TRENDING_LOCAL, null)
    }

    fun saveTrendingJson(context: Context, json: String) {
        prefs(context).edit().putString(KEY_TRENDING_LOCAL, json).apply()
    }
}
