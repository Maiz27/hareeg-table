package com.maiz27.hareegtable

import android.content.Context
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        val preferences = getSharedPreferences("hareeg_table", Context.MODE_PRIVATE)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "hareeg_table/local_storage",
        ).setMethodCallHandler { call, result ->
            val arguments = call.arguments as? Map<*, *>
            val key = arguments?.get("key") as? String

            if (key == null) {
                result.error("invalid_arguments", "A storage key is required.", null)
                return@setMethodCallHandler
            }

            when (call.method) {
                "getString" -> result.success(preferences.getString(key, null))
                "setString" -> {
                    val value = arguments["value"] as? String
                    if (value == null) {
                        result.error("invalid_arguments", "A string value is required.", null)
                    } else {
                        preferences.edit().putString(key, value).apply()
                        result.success(null)
                    }
                }
                "remove" -> {
                    preferences.edit().remove(key).apply()
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }
}
