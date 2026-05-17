package com.veciata.tsmusic

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.graphics.Color
import android.os.Build
import android.util.Log
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetProvider

class SearchWidgetProvider : HomeWidgetProvider() {
    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: SharedPreferences
    ) {
        Log.d("SearchWidget", "onUpdate called for ${appWidgetIds.size} widget(s)")

        val isDarkMode = widgetData.getBoolean("widget_is_dark_mode", false)
        val primaryColor = widgetData.getLong("widget_primary_color", 0xFF1DB954L).toInt()
        val textColor = if (isDarkMode) Color.WHITE else Color.BLACK
        val containerBg = if (isDarkMode) R.drawable.widget_search_edittext_bg_dark
                          else R.drawable.widget_search_edittext_bg_light

        val pendingFlags = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        } else {
            PendingIntent.FLAG_UPDATE_CURRENT
        }

        val searchIntent = Intent(context, MainActivity::class.java).apply {
            action = "com.veciata.tsmusic.OPEN_SEARCH"
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
        }

        for (widgetId in appWidgetIds) {
            try {
                val options = appWidgetManager.getAppWidgetOptions(widgetId)
                val minWidth = options?.getInt(AppWidgetManager.OPTION_APPWIDGET_MIN_WIDTH, 0) ?: 0

                Log.d("SearchWidget", "Widget $widgetId width=$minWidth")

                if (minWidth >= 200) {
                    val views = RemoteViews(context.packageName, R.layout.widget_search_4x1).apply {
                        setInt(R.id.search_4x1_icon, "setColorFilter", primaryColor)
                        setInt(R.id.search_4x1_input_box, "setBackgroundResource", containerBg)
                        setTextColor(R.id.search_4x1_label, textColor)
                        val pi = PendingIntent.getActivity(context, widgetId, searchIntent, pendingFlags)
                        setOnClickPendingIntent(R.id.search_4x1_input_box, pi)
                    }
                    appWidgetManager.updateAppWidget(widgetId, views)
                    Log.d("SearchWidget", "Widget $widgetId → 4x1 layout")
                } else {
                    val views = RemoteViews(context.packageName, R.layout.widget_search_2x1).apply {
                        setInt(R.id.search_2x1_icon, "setColorFilter", primaryColor)
                        setInt(R.id.search_2x1_input_box, "setBackgroundResource", containerBg)
                        setTextColor(R.id.search_2x1_label, textColor)
                        val pi = PendingIntent.getActivity(context, widgetId, searchIntent, pendingFlags)
                        setOnClickPendingIntent(R.id.search_2x1_input_box, pi)
                    }
                    appWidgetManager.updateAppWidget(widgetId, views)
                    Log.d("SearchWidget", "Widget $widgetId → 2x1 layout")
                }
            } catch (e: Exception) {
                Log.e("SearchWidget", "Error updating widget $widgetId: ${e.message}", e)
            }
        }
    }
}
