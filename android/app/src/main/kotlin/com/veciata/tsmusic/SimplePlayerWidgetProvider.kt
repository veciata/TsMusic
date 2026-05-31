package com.veciata.tsmusic

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.graphics.BitmapFactory
import android.graphics.Color
import android.os.Build
import android.os.Bundle
import android.view.KeyEvent
import android.view.View
import android.widget.RemoteViews
import com.ryanheise.audioservice.MediaButtonReceiver
import es.antonborri.home_widget.HomeWidgetProvider
import org.json.JSONArray

class SimplePlayerWidgetProvider : HomeWidgetProvider() {
    override fun onAppWidgetOptionsChanged(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetId: Int,
        newOptions: Bundle,
    ) {
        super.onAppWidgetOptionsChanged(context, appWidgetManager, appWidgetId, newOptions)
        try {
            val data: SharedPreferences = context.getSharedPreferences("HomeWidgetPreferences", Context.MODE_PRIVATE)
            onUpdate(context, appWidgetManager, intArrayOf(appWidgetId), data)
        } catch (_: Exception) {
        }
    }

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: SharedPreferences
    ) {
        val title = widgetData.getString("widget_title", "TS Music") ?: "TS Music"
        val artist = widgetData.getString("widget_artist", "Not playing") ?: "Not playing"
        val isPlaying = widgetData.getBoolean("widget_is_playing", false)
        val isOnline = widgetData.getBoolean("widget_is_online", false)
        val isDarkMode = widgetData.getBoolean("widget_is_dark_mode", false)
        val thumbPath = widgetData.getString("widget_thumbnail", null)
        val queueJson = widgetData.getString("widget_queue", "[]") ?: "[]"

        val defaultPrimary = if (isDarkMode) Color.parseColor("#FFFFFF") else Color.parseColor("#1DB954")
        val primaryColor = try {
            widgetData.getInt("widget_primary_color", defaultPrimary)
        } catch (e: ClassCastException) {
            widgetData.getLong("widget_primary_color", defaultPrimary.toLong()).toInt()
        }
        val bgRes = if (isDarkMode) R.drawable.widget_background_dark
                    else R.drawable.widget_background
        val titleColor = if (isDarkMode) Color.WHITE else Color.BLACK
        val artistColor = if (isDarkMode) Color.parseColor("#BBBBBB") else Color.parseColor("#666666")
        val queueItemColor = if (isDarkMode) Color.parseColor("#999999") else Color.parseColor("#777777")

        val queueItems = try {
            val arr = JSONArray(queueJson)
            val items = mutableListOf<Pair<String, String>>()
            for (i in 0 until arr.length()) {
                val obj = arr.getJSONObject(i)
                val songTitle = obj.optString("title", "Unknown")
                val songArtist = obj.optString("artists", "")
                items.add(Pair(songTitle, songArtist))
            }
            items
        } catch (_: Exception) {
            emptyList()
        }

        val pendingFlags = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        } else {
            PendingIntent.FLAG_UPDATE_CURRENT
        }

        appWidgetIds.forEach { widgetId ->
            try {
                val openAppIntent = Intent(context, MainActivity::class.java).apply {
                    flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
                }
                val openAppPendingIntent = PendingIntent.getActivity(
                    context, widgetId + 3000, openAppIntent, pendingFlags
                )

                fun buildRemoteViews(layoutResId: Int): RemoteViews {
                    return RemoteViews(context.packageName, layoutResId).apply {
                        setInt(R.id.widget_root, "setBackgroundResource", bgRes)
                        setTextViewText(R.id.widget_title, title)
                        setTextViewText(R.id.widget_artist, artist)
                        setTextColor(R.id.widget_title, titleColor)
                        setTextColor(R.id.widget_artist, artistColor)

                        if (thumbPath != null && thumbPath.startsWith("/")) {
                            val bitmap = BitmapFactory.decodeFile(thumbPath)
                            if (bitmap != null) {
                                setImageViewBitmap(R.id.widget_thumbnail, bitmap)
                            } else {
                                setImageViewResource(R.id.widget_thumbnail, android.R.drawable.ic_menu_gallery)
                            }
                        } else {
                            setImageViewResource(R.id.widget_thumbnail, android.R.drawable.ic_menu_gallery)
                        }

                        setOnClickPendingIntent(R.id.widget_thumbnail, openAppPendingIntent)
                        setOnClickPendingIntent(R.id.widget_info_container, openAppPendingIntent)

                        setImageViewResource(
                            R.id.widget_play_pause,
                            if (isPlaying) android.R.drawable.ic_media_pause
                            else android.R.drawable.ic_media_play
                        )

                        val playIntent = Intent(context, MediaButtonReceiver::class.java).apply {
                            action = Intent.ACTION_MEDIA_BUTTON
                            putExtra(Intent.EXTRA_KEY_EVENT,
                                KeyEvent(KeyEvent.ACTION_DOWN, KeyEvent.KEYCODE_MEDIA_PLAY_PAUSE))
                        }
                        val playPendingIntent = PendingIntent.getBroadcast(
                            context, widgetId, playIntent, pendingFlags
                        )
                        setOnClickPendingIntent(R.id.widget_play_pause, playPendingIntent)

                        val prevIntent = Intent(context, MediaButtonReceiver::class.java).apply {
                            action = Intent.ACTION_MEDIA_BUTTON
                            putExtra(Intent.EXTRA_KEY_EVENT,
                                KeyEvent(KeyEvent.ACTION_DOWN, KeyEvent.KEYCODE_MEDIA_PREVIOUS))
                        }
                        val prevPendingIntent = PendingIntent.getBroadcast(
                            context, widgetId + 2000, prevIntent, pendingFlags
                        )
                        setOnClickPendingIntent(R.id.widget_previous, prevPendingIntent)

                        val nextIntent = Intent(context, MediaButtonReceiver::class.java).apply {
                            action = Intent.ACTION_MEDIA_BUTTON
                            putExtra(Intent.EXTRA_KEY_EVENT,
                                KeyEvent(KeyEvent.ACTION_DOWN, KeyEvent.KEYCODE_MEDIA_NEXT))
                        }
                        val nextPendingIntent = PendingIntent.getBroadcast(
                            context, widgetId + 1000, nextIntent, pendingFlags
                        )
                        setOnClickPendingIntent(R.id.widget_next, nextPendingIntent)

                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                            setInt(R.id.widget_play_pause, "setColorFilter", primaryColor)
                            setInt(R.id.widget_previous, "setColorFilter", primaryColor)
                            setInt(R.id.widget_next, "setColorFilter", primaryColor)
                        }

                        val prevNextVisibility = if (isOnline) View.GONE else View.VISIBLE
                        setViewVisibility(R.id.widget_previous, prevNextVisibility)
                        setViewVisibility(R.id.widget_next, prevNextVisibility)

                        if (layoutResId != R.layout.simple_player_widget_compact) {
                            setTextColor(R.id.widget_up_next, primaryColor)

                            val queueItemIds = listOf(
                                R.id.widget_queue_item_1,
                                R.id.widget_queue_item_2,
                                R.id.widget_queue_item_3,
                                R.id.widget_queue_item_4,
                            )
                            for (i in queueItemIds.indices) {
                                if (i < queueItems.size) {
                                    val (songTitle, songArtist) = queueItems[i]
                                    val displayText = if (songArtist.isNotEmpty()) "$songTitle — $songArtist" else songTitle
                                    setTextViewText(queueItemIds[i], displayText)
                                    setTextColor(queueItemIds[i], queueItemColor)
                                    setViewVisibility(queueItemIds[i], View.VISIBLE)
                                    setOnClickPendingIntent(queueItemIds[i], openAppPendingIntent)
                                } else {
                                    setViewVisibility(queueItemIds[i], View.GONE)
                                }
                            }
                        }
                    }
                }

                val views = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                    val viewMapping = mapOf(
                        android.util.SizeF(100f, 40f) to buildRemoteViews(R.layout.simple_player_widget_compact),
                        android.util.SizeF(200f, 100f) to buildRemoteViews(R.layout.simple_player_widget_4x1),
                        android.util.SizeF(200f, 160f) to buildRemoteViews(R.layout.simple_player_widget_4x2)
                    )
                    RemoteViews(viewMapping)
                } else {
                    val options = appWidgetManager.getAppWidgetOptions(widgetId)
                    val minHeight = options?.getInt(AppWidgetManager.OPTION_APPWIDGET_MIN_HEIGHT, 0) ?: 0
                    val currentLayoutRes = when {
                        minHeight < 80 -> R.layout.simple_player_widget_compact
                        minHeight < 160 -> R.layout.simple_player_widget_4x1
                        else -> R.layout.simple_player_widget_4x2
                    }
                    buildRemoteViews(currentLayoutRes)
                }
                appWidgetManager.updateAppWidget(widgetId, views)
            } catch (_: Exception) {
            }
        }
    }
}
