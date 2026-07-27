package com.sokolangu.app

import android.content.Context
import android.content.SharedPreferences

object WidgetDataStore {
    private const val PREFS_NAME = "soko_vibe_widget_data"
    private const val KEY_SALES = "widget_sales"
    private const val KEY_ORDERS = "widget_orders"
    private const val KEY_BALANCE = "widget_balance"
    private const val KEY_TIMESTAMP = "widget_timestamp"

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
}
