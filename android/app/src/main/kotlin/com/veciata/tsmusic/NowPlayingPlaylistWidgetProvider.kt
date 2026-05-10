package com.veciata.tsmusic

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.graphics.Color
import android.view.View
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetPlugin
import es.antonborri.home_widget.HomeWidgetProvider
import org.json.JSONArray

class NowPlayingPlaylistWidgetProvider : HomeWidgetProvider() {

    override fun onReceive(context: Context, intent: Intent) {
        super.onReceive(context, intent)
        if (intent.action == "com.veciata.tsmusic.TOGGLE_PLAYLIST") {
            val prefs = HomeWidgetPlugin.getData(context)
            val collapsed = prefs.getBoolean("playlist_collapsed", true)
            prefs.edit().putBoolean("playlist_collapsed", !collapsed).apply()

            val appWidgetManager = AppWidgetManager.getInstance(context)
            val ids = appWidgetManager.getAppWidgetIds(
                ComponentName(context, NowPlayingPlaylistWidgetProvider::class.java))
            onUpdate(context, appWidgetManager, ids, prefs)
        }
    }

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: android.content.SharedPreferences
    ) {
        val title = widgetData.getString("widget_title", "TS Music") ?: "TS Music"
        val artist = widgetData.getString("widget_artist", "Not playing") ?: "Not playing"
        val isPlaying = widgetData.getBoolean("widget_is_playing", false)
        val isDarkMode = widgetData.getBoolean("widget_is_dark_mode", false)
        val collapsed = widgetData.getBoolean("playlist_collapsed", true)
        val playlistJson = widgetData.getString("playlist_json", "[]") ?: "[]"

        val bgRes = if (isDarkMode) R.drawable.widget_background_dark
                    else R.drawable.widget_background
        val titleColor = if (isDarkMode) Color.WHITE else Color.BLACK
        val artistColor = if (isDarkMode) Color.parseColor("#BBBBBB") else Color.parseColor("#666666")

        appWidgetIds.forEach { widgetId ->
            val views = RemoteViews(context.packageName, R.layout.now_playing_playlist_widget).apply {
                setInt(R.id.playlist_root, "setBackgroundResource", bgRes)
                setTextViewText(R.id.playlist_now_title, title)
                setTextViewText(R.id.playlist_now_artist, artist)
                setTextColor(R.id.playlist_now_title, titleColor)
                setTextColor(R.id.playlist_now_artist, artistColor)

                val queueLabel = context.getString(android.R.string.untitled)
                setTextViewText(R.id.playlist_queue_label, if (isPlaying) "Now Playing" else "Paused")
                setTextColor(R.id.playlist_queue_label, if (isDarkMode) Color.GRAY else Color.GRAY)

                setTextViewText(R.id.playlist_toggle, if (collapsed) "▶" else "▼")

                val toggleIntent = Intent(context, NowPlayingPlaylistWidgetProvider::class.java).apply {
                    action = "com.veciata.tsmusic.TOGGLE_PLAYLIST"
                }
                val togglePendingIntent = PendingIntent.getBroadcast(
                    context, widgetId, toggleIntent,
                    PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
                )
                setOnClickPendingIntent(R.id.playlist_toggle, togglePendingIntent)

                val itemsContainerId = R.id.playlist_items_container
                if (collapsed) {
                    setViewVisibility(itemsContainerId, View.GONE)
                } else {
                    setViewVisibility(itemsContainerId, View.VISIBLE)
                    buildPlaylistItems(context, this, playlistJson, isDarkMode)
                }
            }
            appWidgetManager.updateAppWidget(widgetId, views)
        }
    }

    private fun buildPlaylistItems(
        context: Context,
        views: RemoteViews,
        playlistJson: String,
        isDarkMode: Boolean
    ) {
        val itemColor = if (isDarkMode) Color.parseColor("#CCCCCC") else Color.parseColor("#444444")
        val currentColor = if (isDarkMode) Color.WHITE else Color.BLACK
        val containerId = R.id.playlist_items_container

        views.removeAllViews(containerId)

        try {
            val items = JSONArray(playlistJson)
            val maxItems = minOf(items.length(), 8)

            for (i in 0 until maxItems) {
                val obj = items.getJSONObject(i)
                val songTitle = obj.getString("title")
                val songArtist = obj.optString("artist", "")
                val isCurrent = obj.optBoolean("isCurrent", false)

                val item = RemoteViews(context.packageName, R.layout.now_playing_playlist_item)
                item.setTextViewText(R.id.playlist_item_title, songTitle)
                item.setTextViewText(R.id.playlist_item_artist, songArtist)
                item.setTextColor(R.id.playlist_item_title, if (isCurrent) currentColor else itemColor)
                item.setTextColor(R.id.playlist_item_artist, itemColor)

                views.addView(containerId, item)
            }
        } catch (_: Exception) {
            val empty = RemoteViews(context.packageName, R.layout.now_playing_playlist_item)
            empty.setTextViewText(R.id.playlist_item_title, "No songs in queue")
            empty.setViewVisibility(R.id.playlist_item_artist, View.GONE)
            views.addView(containerId, empty)
        }
    }
}
