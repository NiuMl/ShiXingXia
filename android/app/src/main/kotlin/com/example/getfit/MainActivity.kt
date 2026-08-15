package com.example.getfit

import android.Manifest
import android.app.AppOpsManager
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.PowerManager
import android.provider.Settings
import android.view.WindowManager
import androidx.annotation.NonNull
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.example.getfit/app_blocker"
    private val PREFS_NAME = "app_blocker_prefs"
    private val KEY_BLOCKED_APPS = "blocked_apps"
    private val KEY_BLOCKING_ENABLED = "blocking_enabled"

    /// 通知权限请求的回调（等待用户在系统对话框中操作后返回结果）
    private var notificationPermissionResult: MethodChannel.Result? = null

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
                        // Save to SharedPreferences
                        val prefs = getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
                        prefs.edit().putStringSet(KEY_BLOCKED_APPS, apps.toSet()).apply()

                        // Update the service if it's running
                        AppBlockerService.updateBlockedApps(apps.toSet())
                        result.success(null)
                    } else {
                        result.error("INVALID_ARGUMENT", "Apps list is null", null)
                    }
                }
                "setBlockingEnabled" -> {
                    val enabled = call.argument<Boolean>("enabled")
                    if (enabled != null) {
                        // Save to SharedPreferences
                        val prefs = getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
                        prefs.edit().putBoolean(KEY_BLOCKING_ENABLED, enabled).apply()

                        // Update the service if it's running
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
                "getSocialMediaApps" -> {
                    val apps = getSocialMediaApps()
                    result.success(apps)
                }
                "searchApps" -> {
                    val query = call.argument<String>("query")
                    if (query != null) {
                        val apps = searchApps(query)
                        result.success(apps)
                    } else {
                        result.error("INVALID_ARGUMENT", "Query is null", null)
                    }
                }
                "hasUsageStatsPermission" -> {
                    val hasPermission = hasUsageStatsPermission()
                    result.success(hasPermission)
                }
                "requestUsageStatsPermission" -> {
                    requestUsageStatsPermission()
                    result.success(null)
                }
                "isIgnoringBatteryOptimizations" -> {
                    val isIgnoring = isIgnoringBatteryOptimizations()
                    result.success(isIgnoring)
                }
                "requestIgnoreBatteryOptimizations" -> {
                    requestIgnoreBatteryOptimizations()
                    result.success(null)
                }
                "hasNotificationPermission" -> {
                    val hasPermission = hasNotificationPermission()
                    result.success(hasPermission)
                }
                "requestNotificationPermission" -> {
                    // 不在此处调用 result.success，等 onRequestPermissionsResult 回调后返回
                    requestNotificationPermission(result)
                }
                "setKeepScreenOn" -> {
                    val keepOn = call.argument<Boolean>("keepOn") ?: true
                    runOnUiThread {
                        if (keepOn) {
                            window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                        } else {
                            window.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                        }
                    }
                    result.success(null)
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

    // Social media package name patterns (shared)
    private val socialMediaPatterns = listOf(
        "facebook", "instagram", "tiktok", "twitter", "snapchat",
        "whatsapp", "telegram", "messenger", "reddit", "youtube",
        "linkedin", "pinterest", "tumblr", "discord", "twitch"
    )

    private fun getAppIcon(packageName: String): ByteArray {
        return try {
            val drawable = packageManager.getApplicationIcon(packageName)
            val bitmap = android.graphics.Bitmap.createBitmap(
                drawable.intrinsicWidth,
                drawable.intrinsicHeight,
                android.graphics.Bitmap.Config.ARGB_8888
            )
            val canvas = android.graphics.Canvas(bitmap)
            drawable.setBounds(0, 0, canvas.width, canvas.height)
            drawable.draw(canvas)

            val stream = java.io.ByteArrayOutputStream()
            bitmap.compress(android.graphics.Bitmap.CompressFormat.PNG, 100, stream)
            stream.toByteArray()
        } catch (e: Exception) {
            ByteArray(0)
        }
    }

    private fun getInstalledApps(): List<Map<String, Any>> {
        val pm = packageManager
        val apps = pm.getInstalledApplications(0)

        return apps.filter { appInfo ->
            // Filter out system apps and our own app
            pm.getLaunchIntentForPackage(appInfo.packageName) != null &&
            appInfo.packageName != packageName
        }.map { appInfo ->
            val isSocialMedia = socialMediaPatterns.any {
                appInfo.packageName.lowercase().contains(it)
            }

            mapOf(
                "packageName" to appInfo.packageName,
                "appName" to pm.getApplicationLabel(appInfo).toString(),
                "icon" to getAppIcon(appInfo.packageName),
                "isSocialMedia" to isSocialMedia
            )
        }.sortedWith(compareByDescending<Map<String, Any>> {
            it["isSocialMedia"] as Boolean
        }.thenBy {
            it["appName"] as String
        })
    }

    private fun getSocialMediaApps(): List<Map<String, Any>> {
        val pm = packageManager
        val apps = pm.getInstalledApplications(0)

        // Only return social media apps
        return apps.filter { appInfo ->
            pm.getLaunchIntentForPackage(appInfo.packageName) != null &&
            appInfo.packageName != packageName &&
            socialMediaPatterns.any { appInfo.packageName.lowercase().contains(it) }
        }.map { appInfo ->
            mapOf(
                "packageName" to appInfo.packageName,
                "appName" to pm.getApplicationLabel(appInfo).toString(),
                "icon" to getAppIcon(appInfo.packageName),
                "isSocialMedia" to true
            )
        }.sortedBy { it["appName"] as String }
    }

    private fun searchApps(query: String): List<Map<String, Any>> {
        val pm = packageManager
        val apps = pm.getInstalledApplications(0)
        val lowerQuery = query.lowercase()

        // Search through apps
        return apps.filter { appInfo ->
            pm.getLaunchIntentForPackage(appInfo.packageName) != null &&
            appInfo.packageName != packageName &&
            (pm.getApplicationLabel(appInfo).toString().lowercase().contains(lowerQuery) ||
            appInfo.packageName.lowercase().contains(lowerQuery))
        }.map { appInfo ->
            val isSocialMedia = socialMediaPatterns.any {
                appInfo.packageName.lowercase().contains(it)
            }

            mapOf(
                "packageName" to appInfo.packageName,
                "appName" to pm.getApplicationLabel(appInfo).toString(),
                "icon" to getAppIcon(appInfo.packageName),
                "isSocialMedia" to isSocialMedia
            )
        }.sortedWith(compareByDescending<Map<String, Any>> {
            it["isSocialMedia"] as Boolean
        }.thenBy {
            it["appName"] as String
        }).take(20) // Limit to 20 results for performance
    }

    private fun hasUsageStatsPermission(): Boolean {
        return try {
            val appOpsManager = getSystemService(Context.APP_OPS_SERVICE) as AppOpsManager
            val mode = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                appOpsManager.unsafeCheckOpNoThrow(
                    AppOpsManager.OPSTR_GET_USAGE_STATS,
                    android.os.Process.myUid(),
                    packageName
                )
            } else {
                @Suppress("DEPRECATION")
                appOpsManager.checkOpNoThrow(
                    AppOpsManager.OPSTR_GET_USAGE_STATS,
                    android.os.Process.myUid(),
                    packageName
                )
            }
            mode == AppOpsManager.MODE_ALLOWED
        } catch (e: Exception) {
            false
        }
    }

    private fun requestUsageStatsPermission() {
        val intent = Intent(Settings.ACTION_USAGE_ACCESS_SETTINGS)
        intent.flags = Intent.FLAG_ACTIVITY_NEW_TASK
        startActivity(intent)
    }

    private fun isIgnoringBatteryOptimizations(): Boolean {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            val powerManager = getSystemService(Context.POWER_SERVICE) as PowerManager
            powerManager.isIgnoringBatteryOptimizations(packageName)
        } else {
            true
        }
    }

    private fun requestIgnoreBatteryOptimizations() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            val intent = Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS)
            intent.data = Uri.parse("package:$packageName")
            intent.flags = Intent.FLAG_ACTIVITY_NEW_TASK
            startActivity(intent)
        }
    }

    private fun hasNotificationPermission(): Boolean {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            ContextCompat.checkSelfPermission(
                this,
                Manifest.permission.POST_NOTIFICATIONS
            ) == PackageManager.PERMISSION_GRANTED
        } else {
            // Notifications are granted by default on Android 12 and below
            true
        }
    }

    private fun requestNotificationPermission(result: MethodChannel.Result) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            // 保存 result 引用，等 onRequestPermissionsResult 回调后返回结果
            notificationPermissionResult = result
            requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), 101)
        } else {
            // Android 12 及以下默认有通知权限
            result.success(true)
        }
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == 101) {
            val granted = grantResults.isNotEmpty() &&
                grantResults[0] == PackageManager.PERMISSION_GRANTED
            notificationPermissionResult?.success(granted)
            notificationPermissionResult = null
        }
    }
}
