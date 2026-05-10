package com.veciata.tsmusic

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.Intent
import android.graphics.Color
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetProvider

class SearchWidgetProvider : HomeWidgetProvider() {
    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: android.content.SharedPreferences
    ) {
        val isDarkMode = widgetData.getBoolean("widget_is_dark_mode", false)
        val bgRes = if (isDarkMode) R.drawable.widget_background_dark
                    else R.drawable.widget_background
        val textColor = if (isDarkMode) Color.WHITE else Color.BLACK

        appWidgetIds.forEach { widgetId ->
            val views = RemoteViews(context.packageName, R.layout.search_widget).apply {
                setInt(R.id.search_root, "setBackgroundResource", bgRes)
                setTextColor(R.id.search_text, textColor)

                val intent = Intent(context, MainActivity::class.java).apply {
                    action = "com.veciata.tsmusic.OPEN_SEARCH"
                    flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
                }
                val pendingIntent = PendingIntent.getActivity(
                    context, widgetId, intent,
                    PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
                )
                setOnClickPendingIntent(R.id.search_root, pendingIntent)
            }
            appWidgetManager.updateAppWidget(widgetId, views)
        }
    }
}
