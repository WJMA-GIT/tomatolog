package com.mawj.tomatolog

import android.app.Service
import android.content.Context
import android.content.Intent
import android.graphics.BitmapFactory
import android.graphics.Color
import android.graphics.drawable.GradientDrawable
import android.os.Build
import android.os.IBinder
import android.os.SystemClock
import android.provider.Settings
import android.view.Gravity
import android.view.MotionEvent
import android.view.View
import android.view.WindowManager
import android.widget.Chronometer
import android.widget.ImageView
import android.widget.LinearLayout
import kotlin.math.roundToInt

class FloatingTimerService : Service() {
    private lateinit var windowManager: WindowManager
    private var floatingView: View? = null
    private var positionX: Int? = null
    private var positionY: Int? = null

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            actionShow -> showTimer(intent)
            actionHide -> stopSelf()
        }
        return START_NOT_STICKY
    }

    override fun onDestroy() {
        floatingView?.let { runCatching { windowManager.removeView(it) } }
        floatingView = null
        visible = false
        super.onDestroy()
    }

    private fun showTimer(intent: Intent) {
        if (!Settings.canDrawOverlays(this)) {
            stopSelf()
            return
        }
        if (!::windowManager.isInitialized) {
            windowManager = getSystemService(WINDOW_SERVICE) as WindowManager
        }
        floatingView?.let { windowManager.removeView(it) }

        val remainingSeconds = intent.getIntExtra(extraRemaining, 0).coerceAtLeast(0)
        val deadline = SystemClock.elapsedRealtime() + remainingSeconds * 1000L
        val color = intent.getIntExtra(extraColor, Color.WHITE)
        val view = createView(intent, deadline, color)
        val params = WindowManager.LayoutParams(
            WindowManager.LayoutParams.WRAP_CONTENT,
            WindowManager.LayoutParams.WRAP_CONTENT,
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
            } else {
                @Suppress("DEPRECATION")
                WindowManager.LayoutParams.TYPE_PHONE
            },
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or
                WindowManager.LayoutParams.FLAG_NOT_TOUCH_MODAL,
            android.graphics.PixelFormat.TRANSLUCENT,
        ).apply {
            gravity = Gravity.TOP or Gravity.START
            x = positionX ?: dp(16)
            y = positionY ?: dp(120)
        }
        makeDraggable(view, params)
        windowManager.addView(view, params)
        floatingView = view
        visible = true
    }

    private fun createView(intent: Intent, deadline: Long, color: Int): View {
        val category = intent.getStringExtra(extraCategory).orEmpty()
        val iconBytes = intent.getByteArrayExtra(extraIcon)
        val background = GradientDrawable().apply {
            setColor(Color.argb(205, 32, 33, 36))
            cornerRadius = dp(18).toFloat()
            setStroke(dp(1), Color.argb(70, Color.red(color), Color.green(color), Color.blue(color)))
        }
        return LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            setPadding(dp(12), dp(8), dp(14), dp(8))
            this.background = background
            contentDescription = if (category.isBlank()) "悬浮倒计时" else "$category 悬浮倒计时"

            if (iconBytes != null) {
                addView(ImageView(context).apply {
                    setImageBitmap(BitmapFactory.decodeByteArray(iconBytes, 0, iconBytes.size))
                    setColorFilter(color)
                }, LinearLayout.LayoutParams(dp(28), dp(28)).apply {
                    marginEnd = dp(8)
                })
            }

            addView(Chronometer(context).apply {
                base = deadline
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) isCountDown = true
                format = "%s"
                setTextColor(Color.WHITE)
                textSize = 18f
                typeface = android.graphics.Typeface.DEFAULT_BOLD
                setOnChronometerTickListener {
                    if (SystemClock.elapsedRealtime() >= deadline) {
                        stop()
                        text = "00:00"
                    }
                }
                start()
            })
        }
    }

    private fun makeDraggable(view: View, params: WindowManager.LayoutParams) {
        var startX = 0
        var startY = 0
        var touchX = 0f
        var touchY = 0f
        view.setOnTouchListener { _, event ->
            when (event.action) {
                MotionEvent.ACTION_DOWN -> {
                    startX = params.x
                    startY = params.y
                    touchX = event.rawX
                    touchY = event.rawY
                    true
                }
                MotionEvent.ACTION_MOVE -> {
                    params.x = startX + (event.rawX - touchX).roundToInt()
                    params.y = startY + (event.rawY - touchY).roundToInt()
                    positionX = params.x
                    positionY = params.y
                    windowManager.updateViewLayout(view, params)
                    true
                }
                else -> false
            }
        }
    }

    private fun dp(value: Int) = (value * resources.displayMetrics.density).roundToInt()

    companion object {
        private const val actionShow = "com.mawj.tomatolog.SHOW_FLOATING_TIMER"
        private const val actionHide = "com.mawj.tomatolog.HIDE_FLOATING_TIMER"
        private const val extraCategory = "category"
        private const val extraRemaining = "remaining"
        private const val extraColor = "color"
        private const val extraIcon = "icon"
        @Volatile private var visible = false

        fun show(
            context: Context,
            category: String,
            remainingSeconds: Int,
            color: Int,
            icon: ByteArray?,
        ) {
            if (!Settings.canDrawOverlays(context)) return
            context.startService(Intent(context, FloatingTimerService::class.java).apply {
                action = actionShow
                putExtra(extraCategory, category)
                putExtra(extraRemaining, remainingSeconds)
                putExtra(extraColor, color)
                putExtra(extraIcon, icon)
            })
        }

        fun hide(context: Context) {
            context.stopService(Intent(context, FloatingTimerService::class.java))
        }

        fun updateIfVisible(
            context: Context,
            category: String,
            remainingSeconds: Int,
            color: Int,
            icon: ByteArray?,
        ) {
            if (visible) show(context, category, remainingSeconds, color, icon)
        }
    }
}
