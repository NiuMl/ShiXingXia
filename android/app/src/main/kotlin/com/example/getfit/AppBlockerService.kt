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
    private var sessionStartMillis = 0L
    private var lastDeductionAt = 0L

    // Notification update
    private val notificationUpdateInterval = 500L // Update notification every 500ms for better responsiveness
    private var currentTrackedPackage: String? = null

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
        private const val KEY_EARNED_SECONDS = "flutter.earned_seconds"
        private const val KEY_SPENT_SECONDS = "flutter.spent_seconds"
        private const val KEY_LAST_DEDUCTION_AT = "flutter.last_deduction_at"
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
                "屏幕使用时间追踪",
                NotificationManager.IMPORTANCE_LOW
            ).apply {
                description = "显示在被拦截应用中花费的时间"
                setShowBadge(false)
            }

            // Channel for foreground service notification
            val serviceChannel = NotificationChannel(
                FOREGROUND_NOTIFICATION_CHANNEL_ID,
                "应用拦截服务",
                NotificationManager.IMPORTANCE_LOW
            ).apply {
                description = "保持应用拦截在后台运行"
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
        handler.post(notificationUpdateRunnable)
    }

    private fun stopContinuousCheck() {
        handler.removeCallbacks(checkRunnable)
        handler.removeCallbacks(notificationUpdateRunnable)
    }

    private val notificationUpdateRunnable = object : Runnable {
        override fun run() {
            if (isUsingBlockedApp && currentTrackedPackage != null) {
                showUsageNotification(currentTrackedPackage!!)
            }
            handler.postDelayed(this, notificationUpdateInterval)
        }
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
                // Hide notification and stop tracking when leaving blocked app
                hideUsageNotification()
                currentTrackedPackage = null
                stopTimeTracking()
                return
            }

            // Check if should be blocked
            if (blockedApps.contains(packageName)) {
                // Check if user has earned time
                val timePrefs = getSharedPreferences(TIME_PREFS_NAME, Context.MODE_PRIVATE)
                val earnedSeconds = timePrefs.getLong(KEY_EARNED_SECONDS, 0L).toInt()
                val spentSeconds = timePrefs.getLong(KEY_SPENT_SECONDS, 0L).toInt()
                val availableSeconds = earnedSeconds - spentSeconds

                // Also account for time used in current session (not yet saved to disk)
                val currentTime = System.currentTimeMillis()
                val timeUsedInSession = if (isUsingBlockedApp && sessionStartMillis > 0) {
                    ((currentTime - sessionStartMillis) / 1000).toInt()
                } else {
                    0
                }
                val actualAvailableSeconds = availableSeconds - timeUsedInSession

                if (actualAvailableSeconds > 0) {
                    // User has time available - just show notification, no block
                    if (overlayView != null) {
                        Log.d(TAG, "Removing overlay - user has available time")
                        currentBlockedPackage = null
                        removeOverlay()
                    }

                    // Start tracking time if not already tracking
                    if (!isUsingBlockedApp) {
                        startTimeTracking()
                        Log.d(TAG, "Time tracking started. Available: ${availableSeconds / 60} minutes ${availableSeconds % 60} seconds")
                    }

                    // Track current package for notification updates
                    currentTrackedPackage = packageName

                    // Update spent time every second
                    updateSpentTime()

                    // Initial notification will be shown by notificationUpdateRunnable
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
                currentTrackedPackage = null

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
            val earnedSeconds = timePrefs.getLong(KEY_EARNED_SECONDS, 0L).toInt()
            val spentSeconds = timePrefs.getLong(KEY_SPENT_SECONDS, 0L).toInt()
            val availableSeconds = earnedSeconds - spentSeconds

            // Calculate time used in current session (not yet saved)
            val currentTime = System.currentTimeMillis()
            val timeUsedInSession = if (isUsingBlockedApp && sessionStartMillis > 0) {
                ((currentTime - sessionStartMillis) / 1000).toInt()
            } else {
                0
            }

            // Calculate total seconds left (available minus time used in current session)
            val totalSecondsLeft = maxOf(0, availableSeconds - timeUsedInSession)

            if (totalSecondsLeft <= 0) {
                // No time left, save session time immediately and trigger blocking
                if (isUsingBlockedApp && sessionStartMillis > 0) {
                    val sessionDuration = ((currentTime - sessionStartMillis) / 1000).toInt()
                    if (sessionDuration > 0) {
                        val currentSpent = timePrefs.getLong(KEY_SPENT_SECONDS, 0L).toInt()
                        val newSpent = currentSpent + sessionDuration
                        timePrefs.edit().putLong(KEY_SPENT_SECONDS, newSpent.toLong()).commit()
                        Log.d(TAG, "Time expired! Saved session: ${sessionDuration}s, Total spent: ${newSpent}s")
                    }
                }

                hideUsageNotification()
                // Stop tracking and reset session
                isUsingBlockedApp = false
                sessionStartMillis = 0L
                val expiredPackage = currentTrackedPackage
                currentTrackedPackage = null

                // Directly show block overlay for the current app
                if (expiredPackage != null) {
                    currentBlockedPackage = expiredPackage
                    showBlockOverlay(expiredPackage)
                    Log.d(TAG, "Time expired - showing block overlay immediately")
                }
                return
            }

            // Convert to minutes and seconds for display
            val minutesLeft = totalSecondsLeft / 60
            val secondsLeft = totalSecondsLeft % 60

            val appName = getAppName(packageName)

            val notification = NotificationCompat.Builder(this, NOTIFICATION_CHANNEL_ID)
                .setContentTitle("正在使用 $appName")
                .setContentText("剩余时间：${minutesLeft}分${secondsLeft}秒")
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
        messageTextView.text = "此应用已被拦截。完成运动即可赚取屏幕使用时间！"

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
        if (!isUsingBlockedApp) {
            isUsingBlockedApp = true
            val currentTime = System.currentTimeMillis()

            // Load last deduction time from SharedPreferences
            val timePrefs = getSharedPreferences(TIME_PREFS_NAME, Context.MODE_PRIVATE)
            lastDeductionAt = timePrefs.getLong(KEY_LAST_DEDUCTION_AT, 0L)

            // If no previous tracking or it's been too long (more than 10 seconds), start fresh
            if (lastDeductionAt == 0L || (currentTime - lastDeductionAt) > 10000L) {
                lastDeductionAt = currentTime
                timePrefs.edit().putLong(KEY_LAST_DEDUCTION_AT, lastDeductionAt).commit()
                Log.d(TAG, "Started fresh time tracking at: $lastDeductionAt")
            } else {
                Log.d(TAG, "Resumed time tracking from: $lastDeductionAt")
            }

            sessionStartMillis = currentTime
        }
    }

    private fun stopTimeTracking() {
        if (isUsingBlockedApp) {
            // Deduct time spent in this session before stopping
            val currentTime = System.currentTimeMillis()
            val sessionDuration = ((currentTime - sessionStartMillis) / 1000).toInt() // in seconds

            if (sessionDuration > 0) {
                val timePrefs = getSharedPreferences(TIME_PREFS_NAME, Context.MODE_PRIVATE)
                val currentSpent = timePrefs.getLong(KEY_SPENT_SECONDS, 0L).toInt()
                val newSpent = currentSpent + sessionDuration

                timePrefs.edit().putLong(KEY_SPENT_SECONDS, newSpent.toLong()).commit()
                Log.d(TAG, "Session ended. Duration: ${sessionDuration}s, Total spent: ${newSpent}s")
            }

            isUsingBlockedApp = false
            sessionStartMillis = 0L

            // Reset the deduction timer for next session
            val timePrefs = getSharedPreferences(TIME_PREFS_NAME, Context.MODE_PRIVATE)
            timePrefs.edit().putLong(KEY_LAST_DEDUCTION_AT, 0L).commit()
            lastDeductionAt = 0L

            currentTrackedPackage = null
            Log.d(TAG, "Stopped time tracking and reset timer state")
        }
    }

    private fun updateSpentTime() {
        if (!isUsingBlockedApp) {
            return
        }

        val currentTime = System.currentTimeMillis()
        val timeSinceLastDeduction = currentTime - lastDeductionAt

        // Deduct every second
        if (timeSinceLastDeduction >= 1000L) {
            val secondsToDeduct = (timeSinceLastDeduction / 1000).toInt()

            val timePrefs = getSharedPreferences(TIME_PREFS_NAME, Context.MODE_PRIVATE)
            val currentSpent = timePrefs.getLong(KEY_SPENT_SECONDS, 0L).toInt()
            val currentEarned = timePrefs.getLong(KEY_EARNED_SECONDS, 0L).toInt()
            val currentAvailable = currentEarned - currentSpent

            // Only deduct if there's time available
            if (currentAvailable > 0) {
                val actualDeduction = minOf(secondsToDeduct, currentAvailable)
                val newSpent = currentSpent + actualDeduction

                // Move the deduction time forward
                lastDeductionAt = lastDeductionAt + (actualDeduction * 1000L)

                val editor = timePrefs.edit()
                editor.putLong(KEY_SPENT_SECONDS, newSpent.toLong())
                editor.putLong(KEY_LAST_DEDUCTION_AT, lastDeductionAt)
                editor.commit() // Use commit() for immediate write

                Log.d(TAG, "Deducted ${actualDeduction}s. Total spent: ${newSpent}s (${newSpent/60}m ${newSpent%60}s)")

                // Notification will be updated automatically by notificationUpdateRunnable
            } else {
                Log.d(TAG, "No available time to deduct")
                stopTimeTracking()
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
            .setContentTitle("应用拦截已启动")
            .setContentText("正在后台监控应用使用情况")
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
