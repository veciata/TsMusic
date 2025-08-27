package com.veciata.tsmusic

import android.os.Build
import android.os.Bundle
import android.Manifest
import android.content.pm.PackageManager
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val STORAGE_PERMISSION_REQUEST_CODE = 1001
    private var resultCallback: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        
        // Set up method channel for permission handling
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "com.veciata.tsmusic/permissions").setMethodCallHandler { call, result ->
            when (call.method) {
                "requestStoragePermission" -> {
                    resultCallback = result
                    requestStoragePermission()
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun requestStoragePermission() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            // For Android 13+ (API 33+), use READ_MEDIA_AUDIO
            if (ContextCompat.checkSelfPermission(
                    this,
                    Manifest.permission.READ_MEDIA_AUDIO
                ) != PackageManager.PERMISSION_GRANTED
            ) {
                ActivityCompat.requestPermissions(
                    this,
                    arrayOf(Manifest.permission.READ_MEDIA_AUDIO),
                    STORAGE_PERMISSION_REQUEST_CODE
                )
            } else {
                resultCallback?.success(true)
            }
        } else {
            // For older versions, use READ_EXTERNAL_STORAGE
            if (ContextCompat.checkSelfPermission(
                    this,
                    Manifest.permission.READ_EXTERNAL_STORAGE
                ) != PackageManager.PERMISSION_GRANTED
            ) {
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
