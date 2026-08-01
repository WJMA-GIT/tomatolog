package com.mawj.time_tomato

import android.Manifest
import android.app.Activity
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.PowerManager
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterActivity() {
    private val permissionRequest = 26
    private val backgroundRequest = 27
    private val stopTimerAction = "com.mawj.time_tomato.STOP_TIMER"
    private var pendingNotification: TimerNotification? = null
    private var backgroundResult: MethodChannel.Result? = null
    private var platformChannel: MethodChannel? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        platformChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "time_tomato/platform",
        )
        platformChannel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "requestNotificationPermission" -> {
                    requestNotificationPermission()
                    result.success(null)
                }
                "consumeNotificationAction" ->
                    result.success(consumeNotificationAction())
                "notificationStatus" -> result.success(notificationStatus())
                "requestBatteryOptimizationExemption" -> {
                    requestBatteryOptimizationExemption()
                    result.success(null)
                }
                "openCompletionNotificationSettings" -> {
                    openCompletionNotificationSettings()
                    result.success(null)
                }
                "pickBackgroundImage" -> pickBackgroundImage(result)
                "showTimer" -> {
                    showOrRequestPermission(
                        TimerNotification(
                            category = call.argument<String>("category").orEmpty(),
                            remainingSeconds = call.argument<Int>("remainingSeconds") ?: 0,
                            totalSeconds = call.argument<Int>("totalSeconds") ?: 1,
                            isRunning = call.argument<Boolean>("isRunning") ?: false,
                            color = call.argument<Number>("color")?.toInt() ?: 0,
                            icon = call.argument<ByteArray>("icon"),
                        ),
                    )
                    result.success(null)
                }
                "cancelTimer" -> {
                    pendingNotification = null
                    TimerNotificationService.cancel(this)
                    result.success(null)
                }
                "completeTimer" -> {
                    TimerNotificationService.complete(this)
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        if (consumeNotificationAction() == "stopTimer") {
            platformChannel?.invokeMethod("stopTimer", null)
        }
    }

    private fun consumeNotificationAction(): String? {
        if (intent?.action != stopTimerAction) return null
        intent.action = null
        return "stopTimer"
    }

    private fun requestNotificationPermission() {
        TimerNotificationService.ensureChannels(this)
        val granted =
            Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU ||
                checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) ==
                PackageManager.PERMISSION_GRANTED
        if (granted || Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) return

        val preferences = getSharedPreferences("app_permissions", MODE_PRIVATE)
        val requested = preferences.getBoolean("notification_requested", false)
        if (requested && !shouldShowRequestPermissionRationale(Manifest.permission.POST_NOTIFICATIONS)) {
            startActivity(appNotificationSettingsIntent())
        } else {
            preferences.edit().putBoolean("notification_requested", true).apply()
            requestPermissions(
                arrayOf(Manifest.permission.POST_NOTIFICATIONS),
                permissionRequest,
            )
        }
    }

    private fun notificationStatus(): Map<String, Boolean> {
        val granted =
            Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU ||
                checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) ==
                PackageManager.PERMISSION_GRANTED
        return mapOf(
            "granted" to granted,
            "batteryUnrestricted" to
                (getSystemService(Context.POWER_SERVICE) as PowerManager)
                    .isIgnoringBatteryOptimizations(packageName),
        )
    }

    private fun openCompletionNotificationSettings() {
        TimerNotificationService.ensureChannels(this)
        runCatching { startActivity(appNotificationSettingsIntent()) }
            .onFailure {
                startActivity(
                    Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS).apply {
                        data = Uri.parse("package:$packageName")
                    },
                )
            }
    }

    private fun requestBatteryOptimizationExemption() {
        val powerManager = getSystemService(Context.POWER_SERVICE) as PowerManager
        if (powerManager.isIgnoringBatteryOptimizations(packageName)) return
        val request =
            Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS).apply {
                data = Uri.parse("package:$packageName")
            }
        runCatching { startActivity(request) }.onFailure {
            startActivity(Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS))
        }
    }

    private fun appNotificationSettingsIntent() =
        Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS).apply {
            putExtra(Settings.EXTRA_APP_PACKAGE, packageName)
        }

    private fun pickBackgroundImage(result: MethodChannel.Result) {
        if (backgroundResult != null) {
            result.error("picker_busy", "图片选择器已打开", null)
            return
        }
        backgroundResult = result
        startActivityForResult(
            Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
                addCategory(Intent.CATEGORY_OPENABLE)
                type = "image/*"
            },
            backgroundRequest,
        )
    }

    private fun showOrRequestPermission(notification: TimerNotification) {
        if (
            Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU &&
                checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) !=
                PackageManager.PERMISSION_GRANTED
        ) {
            val shouldRequest = pendingNotification == null
            pendingNotification = notification
            if (shouldRequest) requestNotificationPermission()
            return
        }
        showNotification(notification)
    }

    private fun showNotification(timer: TimerNotification) {
        TimerNotificationService.show(this, timer)
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode != permissionRequest) return
        val notification = pendingNotification
        pendingNotification = null
        val granted = grantResults.firstOrNull() == PackageManager.PERMISSION_GRANTED
        if (granted && notification != null) {
            showNotification(notification)
        }
    }

    override fun onActivityResult(
        requestCode: Int,
        resultCode: Int,
        data: Intent?,
    ) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != backgroundRequest) return
        val result = backgroundResult
        backgroundResult = null
        if (resultCode != Activity.RESULT_OK || data?.data == null) {
            result?.success(null)
            return
        }
        runCatching {
            val destination = File(filesDir, "custom_background")
            contentResolver.openInputStream(data.data!!).use { input ->
                requireNotNull(input) { "无法读取图片" }
                destination.outputStream().use(input::copyTo)
            }
            destination.absolutePath
        }.onSuccess {
            result?.success(it)
        }.onFailure {
            result?.error("image_copy_failed", it.message, null)
        }
    }

}
