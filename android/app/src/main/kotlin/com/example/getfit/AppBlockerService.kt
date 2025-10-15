package com.example.getfit

import android.accessibilityservice.AccessibilityService
import android.accessibilityservice.AccessibilityServiceInfo
import android.app.ActivityManager
import android.app.usage.UsageEvents
import android.app.usage.UsageStatsManager
import android.content.Context
import android.content.Intent
import android.graphics.PixelFormat
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.util.Log
import android.view.Gravity
import android.view.LayoutInflater
import android.view.View
import android.view.WindowManager
import android.view.accessibility.AccessibilityEvent
import android.widget.Button
import android.widget.TextView

class AppBlockerService : AccessibilityService() {
    private var overlayView: View? = null
    private var windowManager: WindowManager? = null
    private var blockedApps: Set<String> = emptySet()
    private var isBlocking = false
    private var currentBlockedPackage: String? = null
    private val handler = Handler(Looper.getMainLooper())
    private val checkInterval = 500L // Check every 500ms

    companion object {
        private const val TAG = "AppBlockerService"
        private const val PREFS_NAME = "app_blocker_prefs"
        private const val KEY_BLOCKED_APPS = "blocked_apps"
        private const val KEY_BLOCKING_ENABLED = "blocking_enabled"
        private var instance: AppBlockerService? = null

        fun getInstance(): AppBlockerService? = instance

        fun updateBlockedApps(apps: Set<String>) {
            instance?.let {
                it.blockedApps = apps
                Log.d(TAG, "Updated blocked apps: ${apps.size} apps")
            }
        }

        fun setBlockingEnabled(enabled: Boolean) {
            instance?.let {
                it.isBlocking = enabled
                Log.d(TAG, "Blocking enabled: $enabled")
            }
        }
    }

    override fun onCreate() {
        super.onCreate()
        instance = this
        windowManager = getSystemService(WINDOW_SERVICE) as WindowManager
        Log.d(TAG, "Service onCreate")

        // Load saved settings from SharedPreferences
        loadSavedSettings()

        // Start continuous checking
        startContinuousCheck()
    }

    private val checkRunnable = object : Runnable {
        override fun run() {
            if (isBlocking) {
                checkForegroundApp()
            }
            handler.postDelayed(this, checkInterval)
        }
    }

    private fun startContinuousCheck() {
        handler.post(checkRunnable)
    }

    private fun stopContinuousCheck() {
        handler.removeCallbacks(checkRunnable)
    }

    private fun checkForegroundApp() {
        try {
            val packageName = getForegroundAppPackage() ?: return

            // Don't block our own app or launcher
            if (packageName == this.packageName ||
                packageName.contains("launcher") ||
                packageName.contains("home")) {
                // Only remove overlay if we're not just transitioning
                if (overlayView != null) {
                    Log.d(TAG, "Home/Our app detected, removing overlay")
                    currentBlockedPackage = null
                    removeOverlay()
                }
                return
            }

            // Check if should be blocked
            if (blockedApps.contains(packageName)) {
                if (currentBlockedPackage != packageName || overlayView == null) {
                    Log.d(TAG, "Detected blocked app in foreground: $packageName")
                    currentBlockedPackage = packageName
                    showBlockOverlay(packageName)
                }
            } else {
                // Not a blocked app - clear overlay if present
                if (overlayView != null) {
                    Log.d(TAG, "Non-blocked app detected: $packageName, removing overlay")
                    currentBlockedPackage = null
                    removeOverlay()
                }
            }
        } catch (e: Exception) {
            Log.e(TAG, "Error checking foreground app", e)
        }
    }

    private fun getForegroundAppPackage(): String? {
        return try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
                // Use UsageStatsManager for Lollipop and above
                val usageStatsManager = getSystemService(Context.USAGE_STATS_SERVICE) as UsageStatsManager
                val time = System.currentTimeMillis()

                // Query events in the last second
                val usageEvents = usageStatsManager.queryEvents(time - 1000, time)
                var lastEvent: UsageEvents.Event? = null

                while (usageEvents.hasNextEvent()) {
                    val event = UsageEvents.Event()
                    usageEvents.getNextEvent(event)

                    // Look for MOVE_TO_FOREGROUND events
                    if (event.eventType == UsageEvents.Event.MOVE_TO_FOREGROUND) {
                        lastEvent = event
                    }
                }

                lastEvent?.packageName
            } else {
                // Fallback to ActivityManager for older versions
                val activityManager = getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager
                val runningTasks = activityManager.getRunningTasks(1)
                if (runningTasks.isNotEmpty()) {
                    runningTasks[0].topActivity?.packageName
                } else {
                    null
                }
            }
        } catch (e: Exception) {
            Log.e(TAG, "Error getting foreground app package", e)
            null
        }
    }

    private fun loadSavedSettings() {
        try {
            val prefs = getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            val appsSet = prefs.getStringSet(KEY_BLOCKED_APPS, emptySet()) ?: emptySet()
            val blockingEnabled = prefs.getBoolean(KEY_BLOCKING_ENABLED, false)

            blockedApps = appsSet
            isBlocking = blockingEnabled

            Log.d(TAG, "Loaded settings - Blocked apps: ${blockedApps.size}, Blocking enabled: $isBlocking")
        } catch (e: Exception) {
            Log.e(TAG, "Error loading saved settings", e)
        }
    }

    override fun onAccessibilityEvent(event: AccessibilityEvent?) {
        // Only using UsageStatsManager polling for detection
        // This is kept to maintain AccessibilityService but does nothing
    }

    private fun showBlockOverlay(packageName: String) {
        if (overlayView != null) {
            // Update existing overlay and ensure it's on top
            updateOverlayContent(packageName)
            try {
                // Bring the overlay back to the front
                overlayView?.bringToFront()
                Log.d(TAG, "Brought overlay to front")
            } catch (e: Exception) {
                Log.e(TAG, "Error bringing overlay to front", e)
            }
            return
        }

        Log.d(TAG, "Creating overlay for: $packageName")

        val params = WindowManager.LayoutParams(
            WindowManager.LayoutParams.MATCH_PARENT,
            WindowManager.LayoutParams.MATCH_PARENT,
            WindowManager.LayoutParams.TYPE_ACCESSIBILITY_OVERLAY,
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or
                    WindowManager.LayoutParams.FLAG_NOT_TOUCH_MODAL or
                    WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN,
            PixelFormat.TRANSLUCENT
        )

        params.gravity = Gravity.CENTER

        overlayView = createOverlayView(packageName)

        try {
            windowManager?.addView(overlayView, params)
            Log.d(TAG, "Overlay added successfully")
        } catch (e: Exception) {
            Log.e(TAG, "Error adding overlay", e)
        }
    }

    private fun createOverlayView(packageName: String): View {
        val inflater = LayoutInflater.from(this)
        val view = inflater.inflate(R.layout.block_overlay, null)

        val appNameTextView = view.findViewById<TextView>(R.id.blockedAppName)
        val messageTextView = view.findViewById<TextView>(R.id.blockMessage)
        val closeButton = view.findViewById<Button>(R.id.closeButton)

        val appName = getAppName(packageName)
        appNameTextView.text = appName
        messageTextView.text = "This app is blocked. Complete exercises to earn screen time!"

        closeButton.setOnClickListener {
            // Return to home screen
            val startMain = Intent(Intent.ACTION_MAIN)
            startMain.addCategory(Intent.CATEGORY_HOME)
            startMain.flags = Intent.FLAG_ACTIVITY_NEW_TASK
            startActivity(startMain)
        }

        return view
    }

    private fun updateOverlayContent(packageName: String) {
        overlayView?.let { view ->
            val appNameTextView = view.findViewById<TextView>(R.id.blockedAppName)
            val appName = getAppName(packageName)
            appNameTextView.text = appName
        }
    }

    private fun getAppName(packageName: String): String {
        return try {
            val pm = packageManager
            val appInfo = pm.getApplicationInfo(packageName, 0)
            pm.getApplicationLabel(appInfo).toString()
        } catch (e: Exception) {
            packageName
        }
    }

    private fun removeOverlay() {
        overlayView?.let {
            try {
                windowManager?.removeView(it)
            } catch (e: Exception) {
                e.printStackTrace()
            }
            overlayView = null
        }
    }

    override fun onInterrupt() {
        removeOverlay()
    }

    override fun onDestroy() {
        super.onDestroy()
        Log.d(TAG, "Service destroyed")
        stopContinuousCheck()
        removeOverlay()
        instance = null
    }

    override fun onServiceConnected() {
        super.onServiceConnected()
        Log.d(TAG, "Service connected")

        val info = AccessibilityServiceInfo()
        info.eventTypes = AccessibilityEvent.TYPE_WINDOW_STATE_CHANGED or
                AccessibilityEvent.TYPE_WINDOW_CONTENT_CHANGED or
                AccessibilityEvent.TYPE_WINDOWS_CHANGED
        info.feedbackType = AccessibilityServiceInfo.FEEDBACK_GENERIC
        info.flags = AccessibilityServiceInfo.FLAG_INCLUDE_NOT_IMPORTANT_VIEWS or
                AccessibilityServiceInfo.FLAG_RETRIEVE_INTERACTIVE_WINDOWS
        info.notificationTimeout = 50

        serviceInfo = info

        // Reload settings when service connects
        loadSavedSettings()
    }
}
