package com.example.getfit

import android.accessibilityservice.AccessibilityService
import android.accessibilityservice.AccessibilityServiceInfo
import android.app.ActivityManager
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
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
import androidx.core.app.NotificationCompat

class AppBlockerService : AccessibilityService() {
    private var overlayView: View? = null
    private var windowManager: WindowManager? = null
    private var blockedApps: Set<String> = emptySet()
    private var isBlocking = false
    private var currentBlockedPackage: String? = null
    private val handler = Handler(Looper.getMainLooper())
    private val checkInterval = 500L // Check every 500ms

    // Time tracking
    private var isUsingBlockedApp = false
    private var timeTrackingStartMillis = 0L
    private var lastMinuteDeductedAt = 0L
    private var lastBlockedAppDetectionTime = 0L

    companion object {
        private const val TAG = "AppBlockerService"
        private const val PREFS_NAME = "app_blocker_prefs"
        private const val KEY_BLOCKED_APPS = "blocked_apps"
        private const val KEY_BLOCKING_ENABLED = "blocking_enabled"
        private const val NOTIFICATION_CHANNEL_ID = "usage_tracking"
        private const val NOTIFICATION_ID = 1002
        private const val FOREGROUND_NOTIFICATION_CHANNEL_ID = "app_blocker_service"
        private const val FOREGROUND_NOTIFICATION_ID = 1001
        private const val TIME_PREFS_NAME = "FlutterSharedPreferences"
        private const val KEY_EARNED_MINUTES = "flutter.earned_minutes"
        private const val KEY_SPENT_MINUTES = "flutter.spent_minutes"
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

        // Create notification channel
        createNotificationChannel()

        // Load saved settings from SharedPreferences
        loadSavedSettings()

        // Start continuous checking
        startContinuousCheck()
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            // Channel for usage tracking notifications
            val usageChannel = NotificationChannel(
                NOTIFICATION_CHANNEL_ID,
                "Screen Time Tracking",
                NotificationManager.IMPORTANCE_LOW
            ).apply {
                description = "Shows time spent in blocked apps"
                setShowBadge(false)
            }

            // Channel for foreground service notification
            val serviceChannel = NotificationChannel(
                FOREGROUND_NOTIFICATION_CHANNEL_ID,
                "App Blocker Service",
                NotificationManager.IMPORTANCE_LOW
            ).apply {
                description = "Keeps app blocker running in background"
                setShowBadge(false)
            }

            val notificationManager = getSystemService(NotificationManager::class.java)
            notificationManager.createNotificationChannel(usageChannel)
            notificationManager.createNotificationChannel(serviceChannel)
        }
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
                // Hide notification when not in blocked app
                hideUsageNotification()
                // DON'T stop time tracking here - might just be a brief transition
                return
            }

            // Check if should be blocked
            if (blockedApps.contains(packageName)) {
                // Check if user has earned minutes
                val timePrefs = getSharedPreferences(TIME_PREFS_NAME, Context.MODE_PRIVATE)
                // Flutter stores integers as Long, so we need to read as Long and convert
                val earnedMinutes = timePrefs.getLong(KEY_EARNED_MINUTES, 0L).toInt()
                val spentMinutes = timePrefs.getLong(KEY_SPENT_MINUTES, 0L).toInt()
                val availableMinutes = earnedMinutes - spentMinutes

                if (availableMinutes > 0) {
                    // User has time available - just show notification, no block
                    if (overlayView != null) {
                        Log.d(TAG, "Removing overlay - user has available time")
                        currentBlockedPackage = null
                        removeOverlay()
                    }

                    // Update last detection time
                    lastBlockedAppDetectionTime = System.currentTimeMillis()

                    // Start tracking time if not already tracking
                    if (!isUsingBlockedApp) {
                        startTimeTracking()
                        Log.d(TAG, "Time tracking started. Available: $availableMinutes minutes")
                    }

                    // Update spent time every minute
                    updateSpentTime()

                    showUsageNotification(packageName)
                } else {
                    // No time available - block the app
                    stopTimeTracking()

                    if (currentBlockedPackage != packageName || overlayView == null) {
                        Log.d(TAG, "Detected blocked app in foreground with no time: $packageName")
                        currentBlockedPackage = packageName
                        showBlockOverlay(packageName)
                    }
                    hideUsageNotification()
                }
            } else {
                // Not a blocked app - clear overlay if present
                stopTimeTracking()

                if (overlayView != null) {
                    Log.d(TAG, "Non-blocked app detected: $packageName, removing overlay")
                    currentBlockedPackage = null
                    removeOverlay()
                }
                hideUsageNotification()
            }
        } catch (e: Exception) {
            Log.e(TAG, "Error checking foreground app", e)
        }
    }

    private fun showUsageNotification(packageName: String) {
        try {
            val timePrefs = getSharedPreferences(TIME_PREFS_NAME, Context.MODE_PRIVATE)
            // Flutter stores integers as Long, so we need to read as Long and convert
            val earnedMinutes = timePrefs.getLong(KEY_EARNED_MINUTES, 0L).toInt()
            val spentMinutes = timePrefs.getLong(KEY_SPENT_MINUTES, 0L).toInt()
            val availableMinutes = earnedMinutes - spentMinutes

            if (availableMinutes <= 0) {
                // No time left, don't show notification
                hideUsageNotification()
                return
            }

            // Calculate seconds remaining in current minute
            val currentTime = System.currentTimeMillis()
            val timeUsedInCurrentMinute = if (isUsingBlockedApp) {
                ((currentTime - lastMinuteDeductedAt) / 1000).toInt()
            } else {
                0
            }
            val secondsRemaining = 60 - timeUsedInCurrentMinute

            val appName = getAppName(packageName)

            val notification = NotificationCompat.Builder(this, NOTIFICATION_CHANNEL_ID)
                .setContentTitle("Using $appName")
                .setContentText("Available: ${availableMinutes}m | Used: ${spentMinutes}m | Next deduction in ${secondsRemaining}s")
                .setSmallIcon(android.R.drawable.ic_dialog_info)
                .setOngoing(true)
                .setPriority(NotificationCompat.PRIORITY_LOW)
                .setCategory(NotificationCompat.CATEGORY_STATUS)
                .setOnlyAlertOnce(true)
                .build()

            val notificationManager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            notificationManager.notify(NOTIFICATION_ID, notification)
        } catch (e: Exception) {
            Log.e(TAG, "Error showing usage notification", e)
        }
    }

    private fun hideUsageNotification() {
        try {
            val notificationManager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            notificationManager.cancel(NOTIFICATION_ID)
        } catch (e: Exception) {
            Log.e(TAG, "Error hiding notification", e)
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

    private fun startTimeTracking() {
        isUsingBlockedApp = true
        timeTrackingStartMillis = System.currentTimeMillis()
        lastMinuteDeductedAt = timeTrackingStartMillis
        Log.d(TAG, "Started time tracking")
    }

    private fun stopTimeTracking() {
        if (isUsingBlockedApp) {
            isUsingBlockedApp = false
            timeTrackingStartMillis = 0L
            lastMinuteDeductedAt = 0L
            Log.d(TAG, "Stopped time tracking")
        }
    }

    private fun updateSpentTime() {
        if (!isUsingBlockedApp) {
            Log.d(TAG, "Not using blocked app, skipping time update")
            return
        }

        val currentTime = System.currentTimeMillis()

        // Check if we haven't detected blocked app for 3 seconds - might have left
        val timeSinceLastDetection = currentTime - lastBlockedAppDetectionTime
        if (timeSinceLastDetection > 3000L) {
            Log.d(TAG, "Haven't detected blocked app for 3s, stopping tracking")
            stopTimeTracking()
            return
        }

        val timeSinceLastDeduction = currentTime - lastMinuteDeductedAt
        val secondsSinceLastDeduction = timeSinceLastDeduction / 1000

        Log.d(TAG, "Time check: ${secondsSinceLastDeduction}s since last deduction (current: $currentTime, last: $lastMinuteDeductedAt)")

        // Deduct a minute every 60 seconds
        if (timeSinceLastDeduction >= 60000L) {
            val minutesToDeduct = (timeSinceLastDeduction / 60000L).toInt()

            if (minutesToDeduct > 0) {
                val timePrefs = getSharedPreferences(TIME_PREFS_NAME, Context.MODE_PRIVATE)
                val currentSpent = timePrefs.getLong(KEY_SPENT_MINUTES, 0L).toInt()
                val newSpent = currentSpent + minutesToDeduct

                Log.d(TAG, "Before write - currentSpent: $currentSpent, newSpent: $newSpent")

                val editor = timePrefs.edit()
                editor.putLong(KEY_SPENT_MINUTES, newSpent.toLong())
                val success = editor.commit() // Use commit() instead of apply() for immediate write

                Log.d(TAG, "Write success: $success. Deducted $minutesToDeduct minute(s). Total spent: $newSpent")

                lastMinuteDeductedAt = currentTime

                // Force notification update to show new time
                currentBlockedPackage?.let { showUsageNotification(it) }
            }
        }
    }

    override fun onInterrupt() {
        removeOverlay()
    }

    override fun onDestroy() {
        super.onDestroy()
        Log.d(TAG, "Service destroyed")
        stopContinuousCheck()
        stopTimeTracking()
        removeOverlay()
        hideUsageNotification()
        instance = null
    }

    private fun startForegroundService() {
        val notification = NotificationCompat.Builder(this, FOREGROUND_NOTIFICATION_CHANNEL_ID)
            .setContentTitle("App Blocker Active")
            .setContentText("Monitoring app usage in background")
            .setSmallIcon(android.R.drawable.ic_menu_view)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setOngoing(true)
            .build()

        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                startForeground(FOREGROUND_NOTIFICATION_ID, notification, android.content.pm.ServiceInfo.FOREGROUND_SERVICE_TYPE_MANIFEST)
            } else {
                startForeground(FOREGROUND_NOTIFICATION_ID, notification)
            }
            Log.d(TAG, "Started as foreground service")
        } catch (e: Exception) {
            Log.e(TAG, "Error starting foreground service", e)
        }
    }

    override fun onServiceConnected() {
        super.onServiceConnected()
        Log.d(TAG, "Service connected")

        // Start as foreground service to prevent being killed
        startForegroundService()

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
