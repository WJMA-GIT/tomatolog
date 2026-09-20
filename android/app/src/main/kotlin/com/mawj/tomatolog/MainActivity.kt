package com.mawj.tomatolog

import android.Manifest
import android.app.Activity
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.PowerManager
import android.provider.Settings
import android.view.View
import android.view.WindowInsets
import android.view.WindowInsetsController
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterActivity() {
    private val permissionRequest = 26
    private val backgroundRequest = 27
    private val backupExportRequest = 28
    private val stopTimerAction = "com.mawj.tomatolog.STOP_TIMER"
    private var pendingNotification: TimerNotification? = null
    private var notificationPermissionResult: MethodChannel.Result? = null
    private var backgroundResult: MethodChannel.Result? = null
    private var backupExportResult: MethodChannel.Result? = null
    private var backupExportBytes: ByteArray? = null
    private var platformChannel: MethodChannel? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        platformChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "tomatolog/platform",
        )
        platformChannel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "requestNotificationPermission" -> {
                    requestNotificationPermission(result)
                }
                "consumeNotificationAction" ->
                    result.success(consumeNotificationAction())
                "notificationStatus" -> result.success(notificationStatus())
                "requestBatteryOptimizationExemption" -> {
                    requestBatteryOptimizationExemption()
                    result.success(null)
                }
                "floatingTimerPermissionGranted" ->
                    result.success(Settings.canDrawOverlays(this))
                "requestFloatingTimerPermission" -> {
                    requestFloatingTimerPermission()
                    result.success(null)
                }
                "showFloatingTimer" -> {
                    FloatingTimerService.show(
                        context = this,
                        category = call.argument<String>("category").orEmpty(),
                        remainingSeconds = call.argument<Int>("remainingSeconds") ?: 0,
                        color = call.argument<Number>("color")?.toInt() ?: 0,
                        icon = call.argument<ByteArray>("icon"),
                    )
                    result.success(null)
                }
                "hideFloatingTimer" -> {
                    FloatingTimerService.hide(this)
                    result.success(null)
                }
                "setKeepScreenOn" -> {
                    setLandscapeDisplayActive(call.arguments == true)
                    result.success(null)
                }
                "openCompletionNotificationSettings" -> {
                    openCompletionNotificationSettings()
                    result.success(null)
                }
                "markNotificationSetupGuideShown" -> {
                    getSharedPreferences("app_permissions", MODE_PRIVATE)
                        .edit()
                        .putBoolean("notification_setup_guide_shown", true)
                        .apply()
                    result.success(null)
                }
                "markBatteryOptimizationGuideShown" -> {
                    getSharedPreferences("app_permissions", MODE_PRIVATE)
                        .edit()
                        .putBoolean("battery_optimization_guide_shown", true)
                        .apply()
                    result.success(null)
                }
                "showCompletionNotificationTest" -> {
                    TimerNotificationService.showCompletionTest(this)
                    result.success(null)
                }
                "pickBackgroundImage" -> pickBackgroundImage(result)
                "exportBackupFile" -> {
                    val fileName = call.argument<String>("fileName")
                    val bytes = call.argument<ByteArray>("bytes")
                    if (fileName.isNullOrBlank() || bytes == null) {
                        result.error("invalid_backup", "备份文件无效", null)
                    } else {
                        exportBackupFile(fileName, bytes, result)
                    }
                }
                "saveBackgroundImage" -> {
                    val bytes = call.arguments as? ByteArray
                    if (bytes == null) {
                        result.error("invalid_image", "备份中的背景图片无效", null)
                    } else {
                        runCatching { saveBackgroundImage(bytes) }
                            .onSuccess(result::success)
                            .onFailure {
                                result.error("image_restore_failed", it.message, null)
                            }
                    }
                }
                "showTimer" -> {
                    showOrRequestPermission(
                        TimerNotification(
                            category = call.argument<String>("category").orEmpty(),
                            remainingSeconds = call.argument<Int>("remainingSeconds") ?: 0,
                            totalSeconds = call.argument<Int>("totalSeconds") ?: 1,
                            color = call.argument<Number>("color")?.toInt() ?: 0,
                            icon = call.argument<ByteArray>("icon"),
                            phase = call.argument<String>("phase") ?: "running",
                            currentCycle = call.argument<Int>("currentCycle") ?: 1,
                            cycleCount = call.argument<Int>("cycleCount") ?: 1,
                            currentGroup = call.argument<Int>("currentGroup") ?: 1,
                            groupCount = call.argument<Int>("groupCount") ?: 1,
                            focusSeconds = call.argument<Int>("focusSeconds") ?: 1,
                            intervalSeconds = call.argument<Int>("intervalSeconds") ?: 1,
                            longIntervalSeconds =
                                call.argument<Int>("longIntervalSeconds") ?: 1,
                        ),
                    )
                    result.success(null)
                }
                "cancelTimer" -> {
                    pendingNotification = null
                    TimerNotificationService.cancel(this)
                    FloatingTimerService.hide(this)
                    result.success(null)
                }
                "completeTimer" -> {
                    TimerNotificationService.complete(this)
                    FloatingTimerService.hide(this)
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

    private fun setLandscapeDisplayActive(active: Boolean) {
        if (active) {
            window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        } else {
            window.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            window.insetsController?.apply {
                systemBarsBehavior =
                    WindowInsetsController.BEHAVIOR_SHOW_TRANSIENT_BARS_BY_SWIPE
                if (active) {
                    hide(WindowInsets.Type.systemBars())
                } else {
                    show(WindowInsets.Type.systemBars())
                }
            }
            return
        }
        @Suppress("DEPRECATION")
        window.decorView.systemUiVisibility = if (active) {
            View.SYSTEM_UI_FLAG_IMMERSIVE_STICKY or
                View.SYSTEM_UI_FLAG_FULLSCREEN or
                View.SYSTEM_UI_FLAG_HIDE_NAVIGATION or
                View.SYSTEM_UI_FLAG_LAYOUT_FULLSCREEN or
                View.SYSTEM_UI_FLAG_LAYOUT_HIDE_NAVIGATION or
                View.SYSTEM_UI_FLAG_LAYOUT_STABLE
        } else {
            View.SYSTEM_UI_FLAG_LAYOUT_STABLE
        }
    }

    override fun onResume() {
        super.onResume()
        FloatingTimerService.hide(this)
    }

    private fun consumeNotificationAction(): String? {
        if (intent?.action != stopTimerAction) return null
        intent.action = null
        return "stopTimer"
    }

    private fun requestNotificationPermission(result: MethodChannel.Result? = null) {
        TimerNotificationService.ensureChannels(this)
        val granted =
            Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU ||
                checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) ==
                PackageManager.PERMISSION_GRANTED
        if (granted || Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) {
            result?.success(null)
            return
        }

        val preferences = getSharedPreferences("app_permissions", MODE_PRIVATE)
        val requested = preferences.getBoolean("notification_requested", false)
        if (requested && !shouldShowRequestPermissionRationale(Manifest.permission.POST_NOTIFICATIONS)) {
            startActivity(appNotificationSettingsIntent())
            result?.success(null)
        } else {
            preferences.edit().putBoolean("notification_requested", true).apply()
            notificationPermissionResult = result
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
        val requested =
            Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU &&
                getSharedPreferences("app_permissions", MODE_PRIVATE)
                    .getBoolean("notification_requested", false)
        val setupGuideShown =
            getSharedPreferences("app_permissions", MODE_PRIVATE)
                .getBoolean("notification_setup_guide_shown", false)
        val batteryGuideShown =
            getSharedPreferences("app_permissions", MODE_PRIVATE)
                .getBoolean("battery_optimization_guide_shown", false)
        return mapOf(
            "granted" to granted,
            "requested" to requested,
            "setupGuideShown" to setupGuideShown,
            "batteryGuideShown" to batteryGuideShown,
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

    private fun requestFloatingTimerPermission() {
        if (Settings.canDrawOverlays(this)) return
        val intent = Intent(
            Settings.ACTION_MANAGE_OVERLAY_PERMISSION,
            Uri.parse("package:$packageName"),
        )
        runCatching { startActivity(intent) }.onFailure {
            startActivity(Intent(Settings.ACTION_MANAGE_OVERLAY_PERMISSION))
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

    private fun saveBackgroundImage(bytes: ByteArray): String {
        require(bytes.isNotEmpty()) { "背景图片为空" }
        return File(filesDir, "custom_background").apply {
            writeBytes(bytes)
        }.absolutePath
    }

    private fun exportBackupFile(
        fileName: String,
        bytes: ByteArray,
        result: MethodChannel.Result,
    ) {
        if (backupExportResult != null) {
            result.error("picker_busy", "文件保存器已打开", null)
            return
        }
        backupExportResult = result
        backupExportBytes = bytes
        startActivityForResult(
            Intent(Intent.ACTION_CREATE_DOCUMENT).apply {
                addCategory(Intent.CATEGORY_OPENABLE)
                type = "application/json"
                putExtra(Intent.EXTRA_TITLE, fileName)
            },
            backupExportRequest,
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
        notificationPermissionResult?.success(null)
        notificationPermissionResult = null
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
        if (requestCode == backupExportRequest) {
            val result = backupExportResult
            val bytes = backupExportBytes
            backupExportResult = null
            backupExportBytes = null
            if (resultCode != Activity.RESULT_OK || data?.data == null) {
                result?.success(false)
                return
            }
            runCatching {
                requireNotNull(bytes) { "备份内容为空" }
                contentResolver.openOutputStream(data.data!!, "w").use { output ->
                    requireNotNull(output) { "无法写入所选文件" }
                    output.write(bytes)
                }
            }.onSuccess {
                result?.success(true)
            }.onFailure {
                result?.error("backup_export_failed", it.message, null)
            }
            return
        }
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
