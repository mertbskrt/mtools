package com.example.mtools_v2

import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.SharedPreferences
import android.os.Bundle
import android.view.View
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetLaunchIntent
import es.antonborri.home_widget.HomeWidgetPlugin
import es.antonborri.home_widget.HomeWidgetProvider
import org.json.JSONArray

/// Proxmox sunucularının (node) durumunu gösteren "Sistem" widget'ı. Veri,
/// uygulama (ProxmoxProvider.refresh()) veya uygulama kapalıyken arka plan
/// bildirim servisi tarafından "proxmox_nodes_json" anahtarına yazılır.
///
/// Widget 3 farklı detay seviyesi arasında geçiş yapar (küçük/orta/büyük) —
/// kullanıcı widget'ı büyüttükçe her node için disk% ve çalışma süresi gibi
/// ek bilgiler görünür. Geçiş, onAppWidgetOptionsChanged'de widget'ın
/// MIN_WIDTH/MIN_HEIGHT seçeneklerine bakılarak elle yapılıyor — bazı
/// launcher'lar (ör. Samsung One UI) Android 12'nin
/// RemoteViews(Map<SizeF,...>) API'sini resize sırasında güvenilir şekilde
/// tetiklemiyor.
///
/// Widget küçük/glanceable bir alan olduğu için en fazla 4 sunucu satırı
/// gösterilir; daha fazlası varsa altta "+N sunucu daha" yazısı çıkar —
/// tam listeyi görmek için uygulamayı açmak gerekir.
class ProxmoxWidgetProvider : HomeWidgetProvider() {
    companion object {
        private const val MAX_ROWS = 4
        private val ROW_IDS = intArrayOf(R.id.node_row_1, R.id.node_row_2, R.id.node_row_3, R.id.node_row_4)
        private val DOT_IDS = intArrayOf(R.id.node_dot_1, R.id.node_dot_2, R.id.node_dot_3, R.id.node_dot_4)
        private val NAME_IDS = intArrayOf(R.id.node_name_1, R.id.node_name_2, R.id.node_name_3, R.id.node_name_4)
        private val STATS_IDS = intArrayOf(R.id.node_stats_1, R.id.node_stats_2, R.id.node_stats_3, R.id.node_stats_4)
        private val BAR_IDS = intArrayOf(R.id.node_bar_1, R.id.node_bar_2, R.id.node_bar_3, R.id.node_bar_4)
        private val UPTIME_IDS = intArrayOf(R.id.node_uptime_1, R.id.node_uptime_2, R.id.node_uptime_3, R.id.node_uptime_4)

        private const val COLOR_ONLINE = 0xFF3DB885.toInt()
        private const val COLOR_OFFLINE = 0xFFD95C5C.toInt()
        private const val COLOR_PARTIAL = 0xFFD4893A.toInt()
    }

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: SharedPreferences,
    ) {
        for (widgetId in appWidgetIds) {
            render(context, appWidgetManager, widgetId)
        }
    }

    override fun onAppWidgetOptionsChanged(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetId: Int,
        newOptions: Bundle,
    ) {
        super.onAppWidgetOptionsChanged(context, appWidgetManager, appWidgetId, newOptions)
        render(context, appWidgetManager, appWidgetId, newOptions)
    }

    private fun render(
        context: Context,
        appWidgetManager: AppWidgetManager,
        widgetId: Int,
        options: Bundle? = null,
    ) {
        val opts = options ?: appWidgetManager.getAppWidgetOptions(widgetId)
        val width = opts.getInt(AppWidgetManager.OPTION_APPWIDGET_MIN_WIDTH, 110)
        val height = opts.getInt(AppWidgetManager.OPTION_APPWIDGET_MIN_HEIGHT, 110)

        val raw = HomeWidgetPlugin.getData(context).getString("proxmox_nodes_json", null)

        // Sadece toplam widget boyutuna bakmak yetmiyor: 1 node ile 4 node
        // aynı alana çok farklı şekilde sığar. Satır başına düşen gerçek
        // alan hesaplanıp ona göre karar veriliyor — aksi halde örn. 3 node
        // küçük bir widget'a sıkıştırılıp yazılar üst üste biniyordu.
        val rowCount = try {
            if (raw != null) JSONArray(raw).length().coerceIn(1, MAX_ROWS) else 1
        } catch (e: Exception) {
            1
        }
        val perRowLarge = (height - 60) / rowCount
        val perRowMedium = (height - 50) / rowCount

        val detailed = width >= 200 && perRowLarge >= 80
        val compact = width < 130 || (!detailed && perRowMedium < 55)
        val layoutId = when {
            detailed -> R.layout.widget_proxmox_large
            compact -> R.layout.widget_proxmox_small
            else -> R.layout.widget_proxmox
        }
        val views = buildViews(context, layoutId, raw, detailed = detailed, compactSummary = compact)
        try {
            val updatedAt = HomeWidgetPlugin.getData(context).getLong("proxmox_updated_at", 0L)
            views.setTextViewText(R.id.proxmox_updated_text, WidgetFormat.relativeUpdatedAt(updatedAt))
        } catch (_: Exception) {
        }
        views.setOnClickPendingIntent(
            R.id.widget_root_proxmox,
            HomeWidgetLaunchIntent.getActivity(context, MainActivity::class.java),
        )
        appWidgetManager.updateAppWidget(widgetId, views)
    }

    private fun buildViews(
        context: Context,
        layoutId: Int,
        raw: String?,
        detailed: Boolean,
        compactSummary: Boolean,
    ): RemoteViews {
        val views = RemoteViews(context.packageName, layoutId)

        val nodes = try {
            if (raw != null) JSONArray(raw) else JSONArray()
        } catch (e: Exception) {
            JSONArray()
        }

        if (nodes.length() == 0) {
            views.setViewVisibility(R.id.proxmox_content, View.GONE)
            views.setViewVisibility(R.id.proxmox_empty_text, View.VISIBLE)
            try {
                views.setViewVisibility(R.id.proxmox_overflow_text, View.GONE)
            } catch (_: Exception) {
            }
            return views
        }

        views.setViewVisibility(R.id.proxmox_content, View.VISIBLE)
        views.setViewVisibility(R.id.proxmox_empty_text, View.GONE)

        var onlineCount = 0
        for (i in 0 until nodes.length()) {
            if (nodes.getJSONObject(i).optBoolean("online", false)) onlineCount++
        }

        val shown = minOf(nodes.length(), MAX_ROWS)
        for (i in 0 until MAX_ROWS) {
            if (i >= shown) {
                try {
                    views.setViewVisibility(ROW_IDS[i], View.GONE)
                } catch (_: Exception) {
                }
                continue
            }
            val node = nodes.getJSONObject(i)
            val online = node.optBoolean("online", false)
            val cpu = node.optInt("cpu", 0)
            val mem = node.optInt("mem", 0)
            val disk = node.optInt("disk", 0)
            val uptime = node.optInt("uptime", 0)
            val temp = if (node.has("temp")) node.optInt("temp", -1) else -1

            try {
                views.setViewVisibility(ROW_IDS[i], View.VISIBLE)
                views.setTextViewText(NAME_IDS[i], node.optString("name", "-"))
                views.setInt(DOT_IDS[i], "setColorFilter", if (online) COLOR_ONLINE else COLOR_OFFLINE)
                views.setTextViewText(
                    STATS_IDS[i],
                    when {
                        !online -> "Çevrimdışı"
                        detailed -> {
                            val tempPart = if (temp >= 0) " · $temp°C" else ""
                            "CPU %$cpu · RAM %$mem · Disk %$disk$tempPart"
                        }
                        else -> "CPU %$cpu · RAM %$mem"
                    },
                )
                views.setProgressBar(BAR_IDS[i], 100, if (online) cpu.coerceIn(0, 100) else 0, false)
                if (detailed) {
                    views.setTextViewText(UPTIME_IDS[i], if (online) WidgetFormat.uptime(uptime) else "")
                }
            } catch (_: Exception) {
            }
        }

        // proxmox_summary_text küçük layout'ta büyük sayı, orta/büyükte
        // başlık yanındaki küçük özet metni olarak yeniden kullanılıyor.
        try {
            views.setTextViewText(
                R.id.proxmox_summary_text,
                if (compactSummary) "$onlineCount/${nodes.length()}" else "$onlineCount/${nodes.length()} çevrimiçi",
            )
        } catch (_: Exception) {
        }
        if (compactSummary) {
            try {
                views.setInt(
                    DOT_IDS[0],
                    "setColorFilter",
                    if (onlineCount == nodes.length()) COLOR_ONLINE else COLOR_PARTIAL,
                )
            } catch (_: Exception) {
            }
        }

        val remaining = nodes.length() - shown
        try {
            if (remaining > 0) {
                views.setViewVisibility(R.id.proxmox_overflow_text, View.VISIBLE)
                views.setTextViewText(R.id.proxmox_overflow_text, "+$remaining sunucu daha")
            } else {
                views.setViewVisibility(R.id.proxmox_overflow_text, View.GONE)
            }
        } catch (_: Exception) {
        }

        return views
    }
}
