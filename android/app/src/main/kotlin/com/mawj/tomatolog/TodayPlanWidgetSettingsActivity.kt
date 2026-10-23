package com.mawj.tomatolog

import android.app.Activity
import android.appwidget.AppWidgetManager
import android.content.ComponentName
import android.content.res.ColorStateList
import android.graphics.Color
import android.graphics.drawable.ColorDrawable
import android.graphics.drawable.GradientDrawable
import android.os.Bundle
import android.view.Gravity
import android.view.View
import android.view.ViewGroup
import android.view.WindowManager
import android.widget.FrameLayout
import android.widget.LinearLayout
import android.widget.RadioButton
import android.widget.RadioGroup
import android.widget.ScrollView
import android.widget.SeekBar
import android.widget.TextView

class TodayPlanWidgetSettingsActivity : Activity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val widgetId = intent.getIntExtra(
            AppWidgetManager.EXTRA_APPWIDGET_ID,
            AppWidgetManager.INVALID_APPWIDGET_ID,
        )
        val info = AppWidgetManager.getInstance(this).getAppWidgetInfo(widgetId)
        if (info?.provider != ComponentName(this, TodayPlanWidgetProvider::class.java)) {
            finish()
            return
        }

        val appearance = TodayPlanWidgetProvider.appearance(this, widgetId)
        var opacity = appearance.opacity
        var fontSize = appearance.fontSizeSp
        val accent = ColorStateList.valueOf(appearance.accentColor)
        window.setBackgroundDrawable(ColorDrawable(Color.TRANSPARENT))
        window.clearFlags(WindowManager.LayoutParams.FLAG_DIM_BEHIND)
        window.setGravity(Gravity.BOTTOM)
        setFinishOnTouchOutside(true)

        val root = FrameLayout(this).apply {
            setPadding(dp(12), dp(12), dp(12), dp(12))
            setOnClickListener { finish() }
        }
        val panel = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(dp(24), dp(24), dp(24), dp(24))
            background = GradientDrawable().apply {
                setColor(appearance.backgroundColor)
                cornerRadius = dp(28).toFloat()
            }
            isClickable = true
        }
        val scroll = ScrollView(this).apply {
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

        fun label(value: String, size: Float = 16f) = TextView(this).apply {
            text = value
            textSize = size
            setTextColor(appearance.textColor)
        }
        panel.addView(label("小部件外观", 20f))
        val opacityLabel = label("背景不透明度  $opacity%").apply {
            setPadding(0, dp(24), 0, dp(8))
        }
        panel.addView(opacityLabel)
        panel.addView(SeekBar(this).apply {
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
                        this@TodayPlanWidgetSettingsActivity, widgetId, opacity, fontSize,
                    )
                }
                override fun onStartTrackingTouch(bar: SeekBar) {}
                override fun onStopTrackingTouch(bar: SeekBar) {}
            })
        }, LinearLayout.LayoutParams(-1, dp(48)))
        panel.addView(label("字号").apply { setPadding(0, dp(20), 0, dp(8)) })
        val sizes = listOf("小" to 12f, "常规" to 15f, "大" to 18f, "特大" to 22f)
        val fontOptions = RadioGroup(this).apply { orientation = RadioGroup.HORIZONTAL }
        sizes.forEach { (name, size) ->
            fontOptions.addView(RadioButton(this).apply {
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
                        this@TodayPlanWidgetSettingsActivity, widgetId, opacity, fontSize,
                    )
                }
            }, RadioGroup.LayoutParams(0, dp(48), 1f))
        }
        panel.addView(fontOptions)
        setContentView(root, ViewGroup.LayoutParams(
            ViewGroup.LayoutParams.MATCH_PARENT,
            ViewGroup.LayoutParams.WRAP_CONTENT,
        ))
        window.setLayout(
            WindowManager.LayoutParams.MATCH_PARENT,
            WindowManager.LayoutParams.WRAP_CONTENT,
        )
    }

    private fun dp(value: Int) = (value * resources.displayMetrics.density).toInt()
}
