package com.veciata.tsmusic

import android.os.Build
import android.os.Bundle
import android.Manifest
import android.content.Intent
import android.content.pm.PackageManager
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import com.ryanheise.audioservice.AudioServiceActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : AudioServiceActivity() {
    private val STORAGE_PERMISSION_REQUEST_CODE = 1001
    private var resultCallback: MethodChannel.Result? = null
    private var navigationChannel: MethodChannel? = null

    // Set when the launcher widget asked to resume playback while the Flutter
    // side had no handler yet (cold start). The Dart layer polls and consumes
    // it once initState registers the navigation channel handler.
    private var pendingWidgetResume = false

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "com.veciata.tsmusic/permissions").setMethodCallHandler { call, result ->
            when (call.method) {
                "requestStoragePermission" -> {
                    resultCallback = result
                    requestStoragePermission()
                }
                else -> result.notImplemented()
            }
        }

        navigationChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "com.veciata.tsmusic/navigation",
        ).apply {
            setMethodCallHandler { call, result ->
                when (call.method) {
                    "getPendingWidgetResume" -> {
                        result.success(pendingWidgetResume)
                        pendingWidgetResume = false
                    }
                    else -> result.notImplemented()
                }
            }
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        handleWidgetIntent(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        handleWidgetIntent(intent)
    }

    private fun handleWidgetIntent(intent: Intent?) {
        when (intent?.action) {
            "com.veciata.tsmusic.OPEN_SEARCH" -> {
                val query = intent.getStringExtra(Intent.EXTRA_TEXT)
                navigationChannel?.invokeMethod("openSearch", query)
            }
            "com.veciata.tsmusic.RESUME_FROM_WIDGET" -> {
                // Warm start: the Dart handler is already registered, so this
                // lands immediately. Cold start: the invoke is dropped, but the
                // flag is picked up by the Dart initState poll.
                pendingWidgetResume = true
                navigationChannel?.invokeMethod("resumePlayback", null)
            }
        }
    }

    private fun requestStoragePermission() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            if (ContextCompat.checkSelfPermission(
                    this,
                    Manifest.permission.READ_MEDIA_AUDIO
            ) != PackageManager.PERMISSION_GRANTED) {
                ActivityCompat.requestPermissions(
                    this,
                    arrayOf(Manifest.permission.READ_MEDIA_AUDIO),
                    STORAGE_PERMISSION_REQUEST_CODE
                )
            } else {
                resultCallback?.success(true)
            }
        } else {
            if (ContextCompat.checkSelfPermission(
                    this,
                    Manifest.permission.READ_EXTERNAL_STORAGE
            ) != PackageManager.PERMISSION_GRANTED) {
                ActivityCompat.requestPermissions(
                    this,
                    arrayOf(Manifest.permission.READ_EXTERNAL_STORAGE),
                    STORAGE_PERMISSION_REQUEST_CODE
                )
            } else {
                resultCallback?.success(true)
            }
        }
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)

        if (requestCode == STORAGE_PERMISSION_REQUEST_CODE) {
            val granted = grantResults.isNotEmpty() && grantResults[0] == PackageManager.PERMISSION_GRANTED
            resultCallback?.success(granted)
            resultCallback = null
        }
    }
}