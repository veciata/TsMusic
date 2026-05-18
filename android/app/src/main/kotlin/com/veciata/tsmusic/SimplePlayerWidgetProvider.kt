package com.veciata.tsmusic

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.Intent
import android.graphics.BitmapFactory
import android.graphics.Color
import android.graphics.PorterDuff
import android.view.KeyEvent
import android.widget.RemoteViews
import com.ryanheise.audioservice.MediaButtonReceiver
import es.antonborri.home_widget.HomeWidgetProvider
import java.io.File

class SimplePlayerWidgetProvider : HomeWidgetProvider() {
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
        val thumbPath = widgetData.getString("widget_thumbnail", null)

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

        appWidgetIds.forEach { widgetId ->
            val openAppIntent = Intent(context, MainActivity::class.java).apply {
                flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
            }
            val openAppPendingIntent = PendingIntent.getActivity(
                context, widgetId + 3000, openAppIntent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )

            val options = appWidgetManager.getAppWidgetOptions(widgetId)
            val minHeight = options?.getInt(AppWidgetManager.OPTION_APPWIDGET_MIN_HEIGHT, 0) ?: 0
            val layoutRes = if (minHeight < 80) R.layout.simple_player_widget_compact
                            else R.layout.simple_player_widget

            val views = RemoteViews(context.packageName, layoutRes).apply {
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
                    context, widgetId, playIntent,
                    PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
                )
                setOnClickPendingIntent(R.id.widget_play_pause, playPendingIntent)

                val prevIntent = Intent(context, MediaButtonReceiver::class.java).apply {
                    action = Intent.ACTION_MEDIA_BUTTON
                    putExtra(Intent.EXTRA_KEY_EVENT,
                        KeyEvent(KeyEvent.ACTION_DOWN, KeyEvent.KEYCODE_MEDIA_PREVIOUS))
                }
                val prevPendingIntent = PendingIntent.getBroadcast(
                    context, widgetId + 2000, prevIntent,
                    PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
                )
                setOnClickPendingIntent(R.id.widget_previous, prevPendingIntent)

                val nextIntent = Intent(context, MediaButtonReceiver::class.java).apply {
                    action = Intent.ACTION_MEDIA_BUTTON
                    putExtra(Intent.EXTRA_KEY_EVENT,
                        KeyEvent(KeyEvent.ACTION_DOWN, KeyEvent.KEYCODE_MEDIA_NEXT))
                }
                val nextPendingIntent = PendingIntent.getBroadcast(
                    context, widgetId + 1000, nextIntent,
                    PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
                )
                setOnClickPendingIntent(R.id.widget_next, nextPendingIntent)

                setInt(R.id.widget_play_pause, "setColorFilter", primaryColor)
                setInt(R.id.widget_previous, "setColorFilter", primaryColor)
                setInt(R.id.widget_next, "setColorFilter", primaryColor)
            }
            appWidgetManager.updateAppWidget(widgetId, views)
        }
    }
}
