package com.example.getfit

import android.accessibilityservice.AccessibilityService
import android.accessibilityservice.AccessibilityServiceInfo
import android.content.Context
import android.content.Intent
import android.graphics.PixelFormat
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
        if (event?.eventType == AccessibilityEvent.TYPE_WINDOW_STATE_CHANGED) {
            val packageName = event.packageName?.toString() ?: return

            Log.d(TAG, "Window state changed: $packageName (currentBlocked=$currentBlockedPackage)")

            // Check if the app should be blocked
            if (isBlocking && blockedApps.contains(packageName)) {
                Log.d(TAG, "App is blocked, showing overlay: $packageName")
                currentBlockedPackage = packageName
                showBlockOverlay(packageName)
                return
            }

            // If it's our own app briefly appearing (e.g., when overlay button launches home intent)
            // Don't remove the overlay - wait for the actual target app
            if (packageName == this.packageName && currentBlockedPackage != null) {
                Log.d(TAG, "Our app briefly appeared, keeping overlay for: $currentBlockedPackage")
                return
            }

            // If switching to launcher or home screen, clear the block
            if (packageName == "com.android.launcher" ||
                packageName == "com.android.launcher3" ||
                packageName.contains("launcher") ||
                packageName.contains("home")) {
                Log.d(TAG, "Switched to launcher/home, removing overlay")
                currentBlockedPackage = null
                removeOverlay()
                return
            }

            // If it's our own app and no blocked app is tracked, clear overlay
            if (packageName == this.packageName) {
                Log.d(TAG, "Our app in foreground, removing overlay")
                currentBlockedPackage = null
                removeOverlay()
                return
            }

            // Different app that's not blocked
            // This is a legitimate switch to another app
            if (currentBlockedPackage != null) {
                Log.d(TAG, "Switched to non-blocked app: $packageName, clearing block state")
            }
            currentBlockedPackage = null
            removeOverlay()
        }
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
        removeOverlay()
        instance = null
    }

    override fun onServiceConnected() {
        super.onServiceConnected()

        val info = AccessibilityServiceInfo()
        info.eventTypes = AccessibilityEvent.TYPE_WINDOW_STATE_CHANGED
        info.feedbackType = AccessibilityServiceInfo.FEEDBACK_GENERIC
        info.flags = AccessibilityServiceInfo.FLAG_INCLUDE_NOT_IMPORTANT_VIEWS
        info.notificationTimeout = 100

        serviceInfo = info

        // Reload settings when service connects
        loadSavedSettings()
    }
}
