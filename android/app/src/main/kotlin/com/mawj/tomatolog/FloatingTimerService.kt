package com.mawj.tomatolog

import android.app.Service
import android.content.Context
import android.content.Intent
import android.graphics.BitmapFactory
import android.graphics.Color
import android.graphics.drawable.GradientDrawable
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.os.SystemClock
import android.provider.Settings
import android.view.Gravity
import android.view.MotionEvent
import android.view.View
import android.view.ViewConfiguration
import android.view.WindowManager
import android.widget.Chronometer
import android.widget.ImageView
import android.widget.LinearLayout
import kotlin.math.roundToInt
import kotlin.random.Random

private const val burnInMovePixels = 120

class FloatingTimerService : Service() {
    private lateinit var windowManager: WindowManager
    private var floatingView: View? = null
    private var positionX: Int? = null
    private var positionY: Int? = null
    private val burnInHandler = Handler(Looper.getMainLooper())
    private val burnInMove = object : Runnable {
        override fun run() {
            val view = floatingView ?: return
            val params = view.layoutParams as? WindowManager.LayoutParams ?: return
            val (_, screenHeight) = screenSize()
            params.y = nextBurnInY(
                currentY = params.y,
                minY = 0,
                maxY = (screenHeight - view.height).coerceAtLeast(0),
                moveDown = Random.nextBoolean(),
            )
            positionY = params.y
            windowManager.updateViewLayout(view, params)
            burnInHandler.postDelayed(this, burnInMoveIntervalMillis)
        }
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            actionShow -> showTimer(intent)
            actionHide -> stopSelf()
        }
        return START_NOT_STICKY
    }

    override fun onDestroy() {
        burnInHandler.removeCallbacks(burnInMove)
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
        burnInHandler.removeCallbacks(burnInMove)

        val remainingSeconds = intent.getIntExtra(extraRemaining, 0).coerceAtLeast(0)
        val deadline = SystemClock.elapsedRealtime() + remainingSeconds * 1000L
        val color = intent.getIntExtra(extraColor, Color.WHITE)
        val view = createView(intent, deadline, color)
        val params = WindowManager.LayoutParams(
            dp(floatingWindowWidthDp),
            dp(floatingWindowHeightDp),
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
        view.post {
            if (floatingView !== view) return@post
            constrainToScreen(view, params)
            burnInHandler.postDelayed(burnInMove, burnInMoveIntervalMillis)
        }
        visible = true
    }

    private fun createView(intent: Intent, deadline: Long, color: Int): View {
        val category = intent.getStringExtra(extraCategory).orEmpty()
        val iconBytes = intent.getByteArrayExtra(extraIcon)
        val background = GradientDrawable().apply {
            setColor(Color.argb(205, 32, 33, 36))
            cornerRadius = dp(12).toFloat()
            setStroke(dp(1), Color.argb(70, Color.red(color), Color.green(color), Color.blue(color)))
        }
        return LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            setPadding(dp(5), dp(4), dp(5), dp(4))
            this.background = background
            contentDescription = if (category.isBlank()) "悬浮倒计时" else "$category 悬浮倒计时"

            if (iconBytes != null) {
                addView(ImageView(context).apply {
                    setImageBitmap(BitmapFactory.decodeByteArray(iconBytes, 0, iconBytes.size))
                    setColorFilter(color)
                }, LinearLayout.LayoutParams(dp(18), dp(18)).apply {
                    marginEnd = dp(4)
                })
            }

            addView(Chronometer(context).apply {
                base = deadline
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) isCountDown = true
                format = "%s"
                setTextColor(Color.WHITE)
                textSize = 14f
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
        var moved = false
        val touchSlop = ViewConfiguration.get(this).scaledTouchSlop
        view.setOnTouchListener { _, event ->
            when (event.action) {
                MotionEvent.ACTION_DOWN -> {
                    startX = params.x
                    startY = params.y
                    touchX = event.rawX
                    touchY = event.rawY
                    moved = false
                    true
                }
                MotionEvent.ACTION_MOVE -> {
                    val deltaX = event.rawX - touchX
                    val deltaY = event.rawY - touchY
                    moved = moved || deltaX * deltaX + deltaY * deltaY > touchSlop * touchSlop
                    val (screenWidth, screenHeight) = screenSize()
                    params.x = (startX + deltaX.roundToInt())
                        .coerceIn(0, (screenWidth - view.width).coerceAtLeast(0))
                    params.y = (startY + deltaY.roundToInt())
                        .coerceIn(0, (screenHeight - view.height).coerceAtLeast(0))
                    positionX = params.x
                    positionY = params.y
                    windowManager.updateViewLayout(view, params)
                    true
                }
                MotionEvent.ACTION_UP -> {
                    if (!moved) {
                        startActivity(Intent(this, MainActivity::class.java).apply {
                            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_REORDER_TO_FRONT)
                        })
                    }
                    true
                }
                MotionEvent.ACTION_CANCEL -> true
                else -> false
            }
        }
    }

    private fun constrainToScreen(view: View, params: WindowManager.LayoutParams) {
        val (screenWidth, screenHeight) = screenSize()
        params.x = params.x.coerceIn(0, (screenWidth - view.width).coerceAtLeast(0))
        params.y = params.y.coerceIn(0, (screenHeight - view.height).coerceAtLeast(0))
        positionX = params.x
        positionY = params.y
        windowManager.updateViewLayout(view, params)
    }

    @Suppress("DEPRECATION")
    private fun screenSize(): Pair<Int, Int> =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            windowManager.currentWindowMetrics.bounds.let { it.width() to it.height() }
        } else {
            resources.displayMetrics.let { it.widthPixels to it.heightPixels }
        }

    private fun dp(value: Int) = (value * resources.displayMetrics.density).roundToInt()

    companion object {
        private const val actionShow = "com.mawj.tomatolog.SHOW_FLOATING_TIMER"
        private const val actionHide = "com.mawj.tomatolog.HIDE_FLOATING_TIMER"
        private const val extraCategory = "category"
        private const val extraRemaining = "remaining"
        private const val extraColor = "color"
        private const val extraIcon = "icon"
        private const val floatingWindowWidthDp = 92
        private const val floatingWindowHeightDp = 30
        private const val burnInMoveIntervalMillis = 120_000L
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

internal fun nextBurnInY(currentY: Int, minY: Int, maxY: Int, moveDown: Boolean): Int {
    val current = currentY.coerceIn(minY, maxY)
    val canMoveUp = current - minY >= burnInMovePixels
    val canMoveDown = maxY - current >= burnInMovePixels
    return when {
        canMoveUp && canMoveDown ->
            current + if (moveDown) burnInMovePixels else -burnInMovePixels
        canMoveDown -> current + burnInMovePixels
        canMoveUp -> current - burnInMovePixels
        else -> (if (moveDown) maxY else minY).coerceIn(minY, maxY)
    }
}
