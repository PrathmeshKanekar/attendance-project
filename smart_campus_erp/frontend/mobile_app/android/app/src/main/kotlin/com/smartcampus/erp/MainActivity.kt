package com.smartcampus.erp

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import android.provider.Settings

class MainActivity: FlutterActivity() {
    private val CHANNEL = "com.smartcampus.erp/security"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            if (call.method == "isMockLocationEnabled") {
                try {
                    val isAllowMockLocation = Settings.Secure.getString(
                        contentResolver,
                        Settings.Secure.ALLOW_MOCK_LOCATION
                    )
                    // Return "0" means mock disabled (safe), "1" means mock enabled (block)
                    if (isAllowMockLocation == "1") {
                        result.success("1")
                    } else {
                        result.success("0")
                    }
                } catch (e: Exception) {
                    result.success("0")
                }
            } else {
                result.notImplemented()
            }
        }
    }
}
