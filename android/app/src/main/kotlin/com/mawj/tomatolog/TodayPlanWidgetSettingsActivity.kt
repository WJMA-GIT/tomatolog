package com.mawj.tomatolog

import android.app.Activity
import android.app.Dialog
import android.app.Service
import android.appwidget.AppWidgetManager
import android.content.BroadcastReceiver
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.res.ColorStateList
import android.graphics.Color
import android.graphics.drawable.ColorDrawable
import android.graphics.drawable.GradientDrawable
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.IBinder
import android.provider.Settings
import android.util.Log
import android.view.ContextThemeWrapper
import android.view.Gravity
import android.view.View
import android.view.ViewGroup
import android.view.WindowManager
import android.widget.Button
import android.widget.FrameLayout
import android.widget.LinearLayout
import android.widget.RadioButton
import android.widget.RadioGroup
import android.widget.ScrollView
import android.widget.SeekBar
import android.widget.TextView
import android.widget.Toast

class TodayPlanWidgetSettingsActivity : Activity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val widgetId = intent.getIntExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, AppWidgetManager.INVALID_APPWIDGET_ID)
        if (AppWidgetManager.getInstance(this).getAppWidgetInfo(widgetId)?.provider !=
            ComponentName(this, TodayPlanWidgetProvider::class.java)) {
            finish()
            return
        }
        if (Settings.canDrawOverlays(this)) {
            openPanelAndFinish()
        } else if (savedInstanceState == null) {
            Toast.makeText(this, "请允许显示在其他应用上层，以便在桌面实时调整小部件", Toast.LENGTH_LONG).show()
            val request = Intent(Settings.ACTION_MANAGE_OVERLAY_PERMISSION, Uri.parse("package:$packageName"))
            runCatching { startActivityForResult(request, 1) }
                .recoverCatching { startActivityForResult(Intent(Settings.ACTION_MANAGE_OVERLAY_PERMISSION), 1) }
                .onFailure {
                    Toast.makeText(this, "无法打开悬浮窗授权，请在系统设置中授权后重试", Toast.LENGTH_LONG).show()
                    finish()
                }
        }
    }

    @Deprecated("Framework activity result callback")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == 1) openPanelAndFinish()
    }

    private fun openPanelAndFinish() {
        if (Settings.canDrawOverlays(this)) {
            runCatching {
                startService(Intent(this, TodayPlanWidgetSettingsService::class.java).apply {
                    putExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, intent.getIntExtra(
                        AppWidgetManager.EXTRA_APPWIDGET_ID, AppWidgetManager.INVALID_APPWIDGET_ID,
                    ))
                })
            }.onFailure {
                Log.w("WidgetSettings", "Could not start widget settings", it)
                Toast.makeText(this, "无法打开小部件设置，请重试", Toast.LENGTH_SHORT).show()
            }
        } else {
            Toast.makeText(this, "未授权悬浮窗，已取消外观设置", Toast.LENGTH_SHORT).show()
        }
        // Leave the launcher visible instead of relying on a transparent activity/task.
        finish()
    }
}

class TodayPlanWidgetSettingsService : Service() {
    private var panelDialog: Dialog? = null
    private val closeReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context?, intent: Intent?) { stopSelf() }
    }

    override fun onCreate() {
        super.onCreate()
        val filter = IntentFilter(Intent.ACTION_SCREEN_OFF).apply {
            addAction(Intent.ACTION_CLOSE_SYSTEM_DIALOGS)
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            registerReceiver(closeReceiver, filter, RECEIVER_NOT_EXPORTED)
        } else {
            @Suppress("DEPRECATION")
            registerReceiver(closeReceiver, filter)
        }
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val widgetId = intent?.getIntExtra(
            AppWidgetManager.EXTRA_APPWIDGET_ID,
            AppWidgetManager.INVALID_APPWIDGET_ID,
        ) ?: AppWidgetManager.INVALID_APPWIDGET_ID
        val info = AppWidgetManager.getInstance(this).getAppWidgetInfo(widgetId)
        if (!Settings.canDrawOverlays(this) ||
            info?.provider != ComponentName(this, TodayPlanWidgetProvider::class.java)) {
            stopSelf()
            return START_NOT_STICKY
        }
        removePanel()
        runCatching { showPanel(widgetId) }.onFailure {
            Log.w("WidgetSettings", "Could not show widget settings overlay", it)
            Toast.makeText(this, "无法显示设置面板，请检查悬浮窗权限后重试", Toast.LENGTH_LONG).show()
            stopSelf()
        }
        return START_NOT_STICKY
    }

    private fun showPanel(widgetId: Int) {
        val context = ContextThemeWrapper(this, R.style.WidgetSettingsTheme)
        val appearance = TodayPlanWidgetProvider.appearance(this, widgetId)
        var opacity = appearance.opacity
        var fontSize = appearance.fontSizeSp
        val accent = ColorStateList.valueOf(appearance.accentColor)
        val root = FrameLayout(context).apply {
            setPadding(dp(12), dp(12), dp(12), dp(12))
            setOnClickListener { stopSelf() }
        }
        val panel = LinearLayout(context).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(dp(24), dp(24), dp(24), dp(24))
            background = GradientDrawable().apply {
                setColor(appearance.backgroundColor)
                cornerRadius = dp(28).toFloat()
            }
            isClickable = true
        }
        val scroll = ScrollView(context).apply {
            isFillViewport = false
            addView(panel, FrameLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.WRAP_CONTENT,
            ))
        }
        root.addView(scroll, FrameLayout.LayoutParams(
            FrameLayout.LayoutParams.MATCH_PARENT,
            FrameLayout.LayoutParams.WRAP_CONTENT,
        ))

        fun label(value: String, size: Float = 16f) = TextView(context).apply {
            text = value
            textSize = size
            setTextColor(appearance.textColor)
        }
        panel.addView(LinearLayout(context).apply {
            gravity = Gravity.CENTER_VERTICAL
            addView(label("小部件外观", 20f), LinearLayout.LayoutParams(0, -2, 1f))
            addView(Button(context, null, android.R.attr.borderlessButtonStyle).apply {
                text = "完成"
                setTextColor(appearance.accentColor)
                contentDescription = "关闭小部件外观设置"
                setOnClickListener { stopSelf() }
            }, LinearLayout.LayoutParams(-2, dp(48)))
        })
        val opacityLabel = label("背景不透明度  $opacity%").apply {
            setPadding(0, dp(24), 0, dp(8))
        }
        panel.addView(opacityLabel)
        panel.addView(SeekBar(context).apply {
            max = 100
            progress = opacity
            progressTintList = accent
            thumbTintList = accent
            contentDescription = "背景不透明度"
            setOnSeekBarChangeListener(object : SeekBar.OnSeekBarChangeListener {
                override fun onProgressChanged(bar: SeekBar, value: Int, fromUser: Boolean) {
                    if (!fromUser) return
                    opacity = value
                    opacityLabel.text = "背景不透明度  $value%"
                    TodayPlanWidgetProvider.saveAppearance(
                        this@TodayPlanWidgetSettingsService, widgetId, opacity, fontSize,
                    )
                }
                override fun onStartTrackingTouch(bar: SeekBar) {}
                override fun onStopTrackingTouch(bar: SeekBar) {}
            })
        }, LinearLayout.LayoutParams(-1, dp(48)))
        panel.addView(label("字号").apply { setPadding(0, dp(20), 0, dp(8)) })
        val sizes = listOf("小" to 12f, "常规" to 15f, "大" to 18f, "特大" to 22f)
        val fontOptions = RadioGroup(context).apply { orientation = RadioGroup.HORIZONTAL }
        sizes.forEach { (name, size) ->
            fontOptions.addView(RadioButton(context).apply {
                id = View.generateViewId()
                text = name
                textSize = 14f
                setTextColor(appearance.textColor)
                buttonTintList = ColorStateList(
                    arrayOf(intArrayOf(android.R.attr.state_checked), intArrayOf()),
                    intArrayOf(appearance.accentColor, appearance.secondaryTextColor),
                )
                isChecked = fontSize == size
                setPadding(0, 0, 0, 0)
                setOnClickListener {
                    fontSize = size
                    TodayPlanWidgetProvider.saveAppearance(
                        this@TodayPlanWidgetSettingsService, widgetId, opacity, fontSize,
                    )
                }
            }, RadioGroup.LayoutParams(0, dp(48), 1f))
        }
        panel.addView(fontOptions)
        val dialog = Dialog(context, R.style.WidgetSettingsTheme).apply {
            setContentView(root)
            setCanceledOnTouchOutside(true)
            setOnDismissListener { stopSelf() }
        }
        panelDialog = dialog
        dialog.window!!.apply {
            setType(if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
            } else {
                @Suppress("DEPRECATION")
                WindowManager.LayoutParams.TYPE_PHONE
            })
            setBackgroundDrawable(ColorDrawable(Color.TRANSPARENT))
            clearFlags(WindowManager.LayoutParams.FLAG_DIM_BEHIND)
            setGravity(Gravity.BOTTOM)
        }
        dialog.show()
        dialog.window!!.setLayout(
            WindowManager.LayoutParams.MATCH_PARENT,
            WindowManager.LayoutParams.WRAP_CONTENT,
        )
    }

    private fun removePanel() {
        panelDialog?.setOnDismissListener(null)
        panelDialog?.dismiss()
        panelDialog = null
    }

    override fun onDestroy() {
        removePanel()
        unregisterReceiver(closeReceiver)
        super.onDestroy()
    }

    private fun dp(value: Int) = (value * resources.displayMetrics.density).toInt()
}
