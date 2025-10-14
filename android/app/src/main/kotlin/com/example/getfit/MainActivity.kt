package com.example.getfit

import android.content.Intent
import android.provider.Settings
import androidx.annotation.NonNull
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.example.getfit/app_blocker"

    override fun configureFlutterEngine(@NonNull flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "isAccessibilityServiceEnabled" -> {
                    val isEnabled = isAccessibilityServiceEnabled()
                    result.success(isEnabled)
                }
                "openAccessibilitySettings" -> {
                    openAccessibilitySettings()
                    result.success(null)
                }
                "setBlockedApps" -> {
                    val apps = call.argument<List<String>>("apps")
                    if (apps != null) {
                        AppBlockerService.updateBlockedApps(apps.toSet())
                        result.success(null)
                    } else {
                        result.error("INVALID_ARGUMENT", "Apps list is null", null)
                    }
                }
                "setBlockingEnabled" -> {
                    val enabled = call.argument<Boolean>("enabled")
                    if (enabled != null) {
                        AppBlockerService.setBlockingEnabled(enabled)
                        result.success(null)
                    } else {
                        result.error("INVALID_ARGUMENT", "Enabled parameter is null", null)
                    }
                }
                "getInstalledApps" -> {
                    val apps = getInstalledApps()
                    result.success(apps)
                }
                else -> {
                    result.notImplemented()
                }
            }
        }
    }

    private fun isAccessibilityServiceEnabled(): Boolean {
        val serviceName = "$packageName/${AppBlockerService::class.java.canonicalName}"
        val enabledServices = Settings.Secure.getString(
            contentResolver,
            Settings.Secure.ENABLED_ACCESSIBILITY_SERVICES
        )
        return enabledServices?.contains(serviceName) == true
    }

    private fun openAccessibilitySettings() {
        val intent = Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS)
        intent.flags = Intent.FLAG_ACTIVITY_NEW_TASK
        startActivity(intent)
    }

    private fun getInstalledApps(): List<Map<String, String>> {
        val pm = packageManager
        val apps = pm.getInstalledApplications(0)

        return apps.filter { appInfo ->
            // Filter out system apps and our own app
            pm.getLaunchIntentForPackage(appInfo.packageName) != null &&
            appInfo.packageName != packageName
        }.map { appInfo ->
            mapOf(
                "packageName" to appInfo.packageName,
                "appName" to pm.getApplicationLabel(appInfo).toString()
            )
        }.sortedBy { it["appName"] }
    }
}
