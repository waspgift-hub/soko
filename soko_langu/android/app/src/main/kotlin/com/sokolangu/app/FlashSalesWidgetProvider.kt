package com.sokolangu.app

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.Context
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.os.Build
import android.util.Log
import android.widget.RemoteViews
import org.json.JSONArray

class FlashSalesWidgetProvider : AppWidgetProvider() {

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray
    ) {
        for (appWidgetId in appWidgetIds) {
            updateAppWidget(context, appWidgetManager, appWidgetId)
        }
    }

    override fun onEnabled(context: Context) {
        // Widget added to home screen
    }

    override fun onDisabled(context: Context) {
        // Last widget removed
    }

    companion object {
        private const val TAG = "FlashWidget"
        private const val MAX_PRODUCTS = 3
        private const val REQUEST_CODE_BASE = 2001

        fun updateAppWidget(
            context: Context,
            appWidgetManager: AppWidgetManager,
            appWidgetId: Int
        ) {
            val views = RemoteViews(context.packageName, R.layout.flash_sales_widget)
            var products = emptyList<FlashProduct>()

            // hw: silently keep the widget usable if no data is available yet
            try {
                val json = WidgetDataStore.loadTrendingJson(context)
                if (!json.isNullOrEmpty()) products = parseProducts(json)
            } catch (e: Exception) {
                Log.e(TAG, "Failed to parse trending data: ${e.message}")
            }

            val header = if (products.isNotEmpty()) "Moto Leo" else "Soko Vibe"
            val subheader = if (products.isNotEmpty()) "Flash Sales" else "Hakuna mauzo ya moto sasa"
            views.setTextViewText(R.id.flash_header_text, header)
            views.setTextViewText(R.id.flash_subheader_text, subheader)

            for (index in 0 until MAX_PRODUCTS) {
                var visible = false
                if (index < products.size) {
                    val p = products[index]
                    setProductSlot(context, views, index, p)
                    visible = true
                }
                views.setViewVisibility(productId(index), if (visible) android.view.View.VISIBLE else android.view.View.GONE)
            }

            val pendingFlags = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            } else {
                PendingIntent.FLAG_UPDATE_CURRENT
            }

            // hw: whole widget opens the flash-sale screen
            val flashSaleIntent = Intent(context, MainActivity::class.java).apply {
                putExtra("route", "/flash-sale")
                this.flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
            }
            views.setOnClickPendingIntent(
                R.id.flash_header_text,
                PendingIntent.getActivity(context, REQUEST_CODE_BASE, flashSaleIntent, pendingFlags)
            )

            for (index in 0 until MAX_PRODUCTS) {
                if (index < products.size) {
                    val route = "/product/${products[index].id}"
                    val productIntent = Intent(context, MainActivity::class.java).apply {
                        putExtra("route", route)
                        this.flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
                    }
                    views.setOnClickPendingIntent(
                        productId(index),
                        PendingIntent.getActivity(context, REQUEST_CODE_BASE + index + 1, productIntent, pendingFlags)
                    )
                }
            }

            appWidgetManager.updateAppWidget(appWidgetId, views)
            loadImagesAsync(context, appWidgetManager, appWidgetId, views, products)
        }

        private fun parseProducts(json: String): List<FlashProduct> {
            val array = JSONArray(json)
            return buildList {
                for (i in 0 until array.length()) {
                    val obj = array.optJSONObject(i) ?: continue
                    val product = FlashProduct(
                        id = obj.optString("id", ""),
                        name = obj.optString("name", ""),
                        price = obj.optDouble("price", 0.0),
                        discountedPrice = obj.optDouble("discountedPrice", 0.0),
                        discountPercent = obj.optDouble("discountPercent", 0.0),
                        image = obj.optString("image", "")
                    )
                    if (product.id.isNotEmpty() || product.name.isNotEmpty()) add(product)
                }
            }.take(MAX_PRODUCTS)
        }

        private fun setProductSlot(context: Context, views: RemoteViews, index: Int, product: FlashProduct) {
            views.setTextViewText(nameId(index), product.name)
            views.setTextViewText(priceId(index), formatTZS(product.discountedPrice))
            if (product.discountPercent > 0) {
                views.setTextViewText(discountId(index), "-${product.discountPercent.toInt()}%")
                views.setViewVisibility(discountId(index), android.view.View.VISIBLE)
            } else {
                views.setViewVisibility(discountId(index), android.view.View.GONE)
            }
            if (product.discountedPrice > 0 && product.price > product.discountedPrice) {
                views.setTextViewText(origPriceId(index), formatTZS(product.price))
                views.setViewVisibility(origPriceId(index), android.view.View.VISIBLE)
            } else {
                views.setViewVisibility(origPriceId(index), android.view.View.GONE)
            }
        }

        private fun loadImagesAsync(
            context: Context,
            appWidgetManager: AppWidgetManager,
            appWidgetId: Int,
            views: RemoteViews,
            products: List<FlashProduct>
        ) {
            Thread {
                try {
                    for (index in products.indices) {
                        val url = products[index].image
                        if (url.isEmpty()) continue
                        val bitmap = downloadImage(url) ?: continue
                        views.setImageViewBitmap(imgId(index), bitmap)
                    }
                    appWidgetManager.updateAppWidget(appWidgetId, views)
                } catch (e: Exception) {
                    Log.e(TAG, "Image load failed: ${e.message}")
                }
            }.start()
        }

        private fun downloadImage(url: String): Bitmap? {
            return try {
                // hw: 5s network timeout keeps the widget snappy during cold widget renders
                val connection = java.net.URL(url).openConnection()
                connection.connectTimeout = 5000
                connection.readTimeout = 5000
                val stream = connection.getInputStream()
                val bitmap = BitmapFactory.decodeStream(stream)
                stream.close()
                bitmap
            } catch (e: Exception) {
                Log.e(TAG, "Download failed: ${e.message}")
                null
            }
        }

        private fun formatTZS(value: Double): String {
            val rounded = Math.round(value)
            val formatted = String.format("%,d", rounded).replace(",", ",")
            return "TZS $formatted"
        }

        private fun productId(index: Int) = when (index) {
            0 -> R.id.flash_product_1
            1 -> R.id.flash_product_2
            else -> R.id.flash_product_3
        }

        private fun imgId(index: Int) = when (index) {
            0 -> R.id.flash_img_1
            1 -> R.id.flash_img_2
            else -> R.id.flash_img_3
        }

        private fun nameId(index: Int) = when (index) {
            0 -> R.id.flash_name_1
            1 -> R.id.flash_name_2
            else -> R.id.flash_name_3
        }

        private fun discountId(index: Int) = when (index) {
            0 -> R.id.flash_discount_1
            1 -> R.id.flash_discount_2
            else -> R.id.flash_discount_3
        }

        private fun priceId(index: Int) = when (index) {
            0 -> R.id.flash_price_1
            1 -> R.id.flash_price_2
            else -> R.id.flash_price_3
        }

        private fun origPriceId(index: Int) = when (index) {
            0 -> R.id.flash_origprice_1
            1 -> R.id.flash_origprice_2
            else -> R.id.flash_origprice_3
        }
    }
}

data class FlashProduct(
    val id: String,
    val name: String,
    val price: Double,
    val discountedPrice: Double,
    val discountPercent: Double,
    val image: String
)