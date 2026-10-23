package com.mawj.tomatolog

import android.app.AlarmManager
import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.res.Configuration
import android.graphics.Color
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.util.TypedValue
import android.view.View
import android.widget.RemoteViews
import android.widget.RemoteViewsService
import android.widget.Toast
import org.json.JSONObject
import java.text.SimpleDateFormat
import java.util.Calendar
import java.util.Locale

internal fun todayPlanOccursOn(start: String, end: String, day: String): Boolean {
    val first = start.take(10)
    val last = end.take(10)
    return first.length == 10 && last.length == 10 && day >= first && day <= last
}

data class TodayPlanWidgetAppearance(
    val backgroundColor: Int,
    val textColor: Int,
    val secondaryTextColor: Int,
    val accentColor: Int,
    val opacity: Int,
    val fontSizeSp: Float,
    val followsSystem: Boolean,
)

private fun RemoteViews.themeColor(id: Int, method: String, appearance: TodayPlanWidgetAppearance,
    color: Int, light: Int = color, dark: Int = color) {
    if (appearance.followsSystem && Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
        setColorInt(id, method, light, dark)
    } else {
        setInt(id, method, color)
    }
}

private data class TodayWidgetPlan(
    val id: String,
    val category: String,
    val minutes: Int,
    val completed: Boolean,
) {
    fun views(context: Context, appearance: TodayPlanWidgetAppearance) = RemoteViews(context.packageName, R.layout.today_plan_widget_row).apply {
        setTextViewText(R.id.plan_status, if (completed) "✓" else "○")
        setTextColor(R.id.plan_status, appearance.accentColor)
        setTextViewText(R.id.plan_category, category)
        themeColor(R.id.plan_category, "setTextColor", appearance,
            if (completed) appearance.secondaryTextColor else appearance.textColor,
            if (completed) 0xFF666666.toInt() else 0xFF202020.toInt(),
            if (completed) 0xFFB0B0B0.toInt() else Color.WHITE)
        themeColor(R.id.plan_minutes, "setTextColor", appearance, appearance.secondaryTextColor,
            0xFF666666.toInt(), 0xFFB0B0B0.toInt())
        setTextViewTextSize(R.id.plan_category, TypedValue.COMPLEX_UNIT_SP, appearance.fontSizeSp)
        setTextViewTextSize(R.id.plan_minutes, TypedValue.COMPLEX_UNIT_SP, appearance.fontSizeSp - 3f)
        setTextViewText(R.id.plan_minutes, "$minutes 分钟${if (completed) " · 已完成" else ""}")
        setContentDescription(R.id.plan_row, "$category，$minutes 分钟，${if (completed) "已完成" else "未完成"}，点击配置计时")
        setOnClickFillInIntent(R.id.plan_row, Intent().putExtra(TodayPlanWidgetProvider.PLAN_ID_EXTRA, id))
    }
}

class TodayPlanWidgetProvider : AppWidgetProvider() {
    override fun onUpdate(context: Context, manager: AppWidgetManager, ids: IntArray) {
        updateAll(context)
    }

    override fun onReceive(context: Context, intent: Intent) {
        super.onReceive(context, intent)
        if (intent.action in setOf(REFRESH_ACTION, Intent.ACTION_DATE_CHANGED,
                Intent.ACTION_TIME_CHANGED, Intent.ACTION_TIMEZONE_CHANGED, Intent.ACTION_BOOT_COMPLETED,
                Intent.ACTION_CONFIGURATION_CHANGED)) {
            updateAll(context)
        }
    }

    override fun onAppWidgetOptionsChanged(context: Context, manager: AppWidgetManager, id: Int, options: Bundle) {
        updateAll(context)
    }

    override fun onDeleted(context: Context, ids: IntArray) {
        context.getSharedPreferences(PREFERENCES, Context.MODE_PRIVATE).edit().apply {
            ids.forEach { id -> remove("opacity_$id"); remove("font_size_$id") }
        }.apply()
    }

    override fun onDisabled(context: Context) {
        (context.getSystemService(Context.ALARM_SERVICE) as AlarmManager).cancel(midnightIntent(context))
    }

    companion object {
        const val OPEN_PLAN_ACTION = "com.mawj.tomatolog.OPEN_PLAN_TIMER"
        const val PLAN_ID_EXTRA = "widget_plan_id"
        private const val REFRESH_ACTION = "com.mawj.tomatolog.REFRESH_TODAY_PLANS"
        private const val PREFERENCES = "today_plan_widget"

        fun appearance(context: Context, id: Int): TodayPlanWidgetAppearance {
            val preferences = context.getSharedPreferences(PREFERENCES, Context.MODE_PRIVATE)
            val root = runCatching { JSONObject(preferences.getString("data", "{}") ?: "{}") }
                .getOrElse { JSONObject() }
            val theme = root.optString("themePreference", "system")
            val dark = theme == "dark" || (theme != "light" &&
                context.resources.configuration.uiMode and Configuration.UI_MODE_NIGHT_MASK == Configuration.UI_MODE_NIGHT_YES)
            val font = preferences.getFloat("font_size_$id", 15f)
            return TodayPlanWidgetAppearance(
                if (dark) Color.BLACK else 0xFFF7F7F7.toInt(),
                if (dark) Color.WHITE else 0xFF202020.toInt(),
                if (dark) 0xFFB0B0B0.toInt() else 0xFF666666.toInt(),
                root.optLong("accentColorValue", 0xFFE05446).toInt() or 0xFF000000.toInt(),
                preferences.getInt("opacity_$id", 100).coerceIn(0, 100),
                if (font.isFinite()) font.coerceIn(12f, 22f) else 15f,
                theme != "light" && theme != "dark",
            )
        }

        fun saveAppearance(context: Context, id: Int, opacity: Int, fontSizeSp: Float) {
            context.getSharedPreferences(PREFERENCES, Context.MODE_PRIVATE).edit()
                .putInt("opacity_$id", opacity.coerceIn(0, 100))
                .putFloat("font_size_$id", if (fontSizeSp.isFinite()) fontSizeSp.coerceIn(12f, 22f) else 15f)
                .apply()
            updateAll(context)
        }

        fun saveData(context: Context, data: String) {
            val parsed = JSONObject(data)
            require(parsed.optJSONArray("plans") != null && parsed.optJSONArray("categories") != null)
            context.getSharedPreferences(PREFERENCES, Context.MODE_PRIVATE).edit()
                .putString("data", data).apply()
            updateAll(context)
        }

        fun requestPin(context: Context): Boolean {
            if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return pinUnsupported(context)
            val manager = AppWidgetManager.getInstance(context)
            if (!manager.isRequestPinAppWidgetSupported) return pinUnsupported(context)
            return manager.requestPinAppWidget(ComponentName(context, TodayPlanWidgetProvider::class.java), null, null)
                .also { requested -> if (!requested) pinUnsupported(context) }
        }

        private fun pinUnsupported(context: Context): Boolean {
            Toast.makeText(context, "请长按桌面 → 小部件 → 番茄日志，添加今日计划", Toast.LENGTH_LONG).show()
            return false
        }

        private fun dayKey() = SimpleDateFormat("yyyy-MM-dd", Locale.ROOT).format(Calendar.getInstance().time)

        private fun plans(context: Context): List<TodayWidgetPlan> {
            val source = context.getSharedPreferences(PREFERENCES, Context.MODE_PRIVATE)
                .getString("data", null) ?: return emptyList()
            return runCatching {
                val root = JSONObject(source)
                val categories = root.getJSONArray("categories")
                val names = buildMap<String, String> {
                    for (index in 0 until categories.length()) {
                        val category = categories.getJSONObject(index)
                        if (!category.optBoolean("isArchived", false)) {
                            put(category.getString("id"), category.getString("name"))
                        }
                    }
                }
                val day = dayKey()
                val allPlans = root.getJSONArray("plans")
                buildList {
                    for (index in 0 until allPlans.length()) {
                        val plan = allPlans.getJSONObject(index)
                        val category = names[plan.optString("categoryId")] ?: continue
                        if (!todayPlanOccursOn(plan.optString("startDate"), plan.optString("endDate"), day)) continue
                        val id = plan.optString("id")
                        val minutes = plan.optInt("plannedMinutes")
                        if (id.isBlank() || minutes !in 1..1440) continue
                        val completed = plan.optJSONArray("completedDates")
                        add(TodayWidgetPlan(id, category, minutes,
                            completed != null && (0 until completed.length()).any { completed.optString(it) == day }))
                    }
                }
            }.getOrDefault(emptyList())
        }

        fun updateAll(context: Context) {
            val manager = AppWidgetManager.getInstance(context)
            val ids = manager.getAppWidgetIds(ComponentName(context, TodayPlanWidgetProvider::class.java))
            if (ids.isEmpty()) return
            val todayPlans = plans(context)
            ids.forEach { id ->
                val views = RemoteViews(context.packageName, R.layout.today_plan_widget)
                val appearance = appearance(context, id)
                views.themeColor(R.id.widget_background, "setColorFilter", appearance, appearance.backgroundColor,
                    0xFFF7F7F7.toInt(), Color.BLACK)
                views.setInt(R.id.widget_background, "setImageAlpha", appearance.opacity * 255 / 100)
                views.setTextColor(R.id.widget_title, appearance.accentColor)
                views.setInt(R.id.widget_settings, "setColorFilter", appearance.accentColor)
                views.themeColor(R.id.widget_date, "setTextColor", appearance, appearance.secondaryTextColor,
                    0xFF666666.toInt(), 0xFFB0B0B0.toInt())
                views.themeColor(R.id.widget_empty, "setTextColor", appearance, appearance.secondaryTextColor,
                    0xFF666666.toInt(), 0xFFB0B0B0.toInt())
                views.setTextViewTextSize(R.id.widget_title, TypedValue.COMPLEX_UNIT_SP, appearance.fontSizeSp + 3f)
                views.setTextViewTextSize(R.id.widget_date, TypedValue.COMPLEX_UNIT_SP, appearance.fontSizeSp - 3f)
                views.setTextViewTextSize(R.id.widget_empty, TypedValue.COMPLEX_UNIT_SP, appearance.fontSizeSp)
                val date = SimpleDateFormat("M月d日", Locale.CHINA).format(Calendar.getInstance().time)
                views.setTextViewText(R.id.widget_date, "$date · ${todayPlans.count { it.completed }}/${todayPlans.size}")
                views.setViewVisibility(R.id.widget_empty, if (todayPlans.isEmpty()) View.VISIBLE else View.GONE)
                views.setViewVisibility(R.id.widget_plans, if (todayPlans.isEmpty()) View.GONE else View.VISIBLE)
                val openApp = Intent(context, MainActivity::class.java)
                    .addFlags(Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP)
                views.setOnClickPendingIntent(R.id.widget_header, PendingIntent.getActivity(context, id,
                    openApp, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE))
                val settings = Intent(context, TodayPlanWidgetSettingsActivity::class.java)
                    .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP)
                    .putExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, id)
                    .setData(Uri.parse("tomatolog://today-widget-settings/$id"))
                views.setOnClickPendingIntent(R.id.widget_settings, PendingIntent.getActivity(context, id,
                    settings, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE))
                val template = Intent(openApp).setAction(OPEN_PLAN_ACTION)
                    .setData(Uri.parse("tomatolog://today-widget/$id"))
                val mutable = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) PendingIntent.FLAG_MUTABLE else 0
                views.setPendingIntentTemplate(R.id.widget_plans, PendingIntent.getActivity(context, id,
                    template, PendingIntent.FLAG_UPDATE_CURRENT or mutable))
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                    val items = RemoteViews.RemoteCollectionItems.Builder()
                        .setHasStableIds(false)
                        .setViewTypeCount(1)
                    todayPlans.forEachIndexed { index, plan -> items.addItem(index.toLong(), plan.views(context, appearance)) }
                    views.setRemoteAdapter(R.id.widget_plans, items.build())
                } else {
                    views.setRemoteAdapter(R.id.widget_plans,
                        Intent(context, TodayPlanWidgetService::class.java).apply {
                            putExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, id)
                            data = Uri.parse("tomatolog://today-widget-list/$id")
                        })
                }
                manager.updateAppWidget(id, views)
            }
            if (Build.VERSION.SDK_INT < Build.VERSION_CODES.S) {
                @Suppress("DEPRECATION")
                manager.notifyAppWidgetViewDataChanged(ids, R.id.widget_plans)
            }
            val midnight = Calendar.getInstance().apply {
                add(Calendar.DAY_OF_MONTH, 1)
                set(Calendar.HOUR_OF_DAY, 0)
                set(Calendar.MINUTE, 0)
                set(Calendar.SECOND, 0)
                set(Calendar.MILLISECOND, 0)
            }
            // Widgets refresh at the next allowed opportunity during device sleep.
            (context.getSystemService(Context.ALARM_SERVICE) as AlarmManager)
                .setAndAllowWhileIdle(AlarmManager.RTC, midnight.timeInMillis, midnightIntent(context))
        }

        private fun midnightIntent(context: Context) = PendingIntent.getBroadcast(context, 0,
            Intent(context, TodayPlanWidgetProvider::class.java).setAction(REFRESH_ACTION),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)

        internal fun factory(context: Context, id: Int): RemoteViewsService.RemoteViewsFactory = object : RemoteViewsService.RemoteViewsFactory {
            private var rows = emptyList<TodayWidgetPlan>()
            private var appearance = appearance(context, id)
            override fun onCreate() { rows = plans(context) }
            override fun onDataSetChanged() { rows = plans(context); appearance = appearance(context, id) }
            override fun onDestroy() { rows = emptyList() }
            override fun getCount() = rows.size
            override fun getViewAt(position: Int): RemoteViews? = rows.getOrNull(position)?.views(context, appearance)
            override fun getLoadingView(): RemoteViews? = null
            override fun getViewTypeCount() = 1
            override fun getItemId(position: Int) = position.toLong()
            override fun hasStableIds() = false
        }
    }
}

class TodayPlanWidgetService : RemoteViewsService() {
    override fun onGetViewFactory(intent: Intent) = TodayPlanWidgetProvider.factory(applicationContext,
        intent.getIntExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, AppWidgetManager.INVALID_APPWIDGET_ID))
}
