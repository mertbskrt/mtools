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
import org.json.JSONObject
import java.util.Locale

/// UPS (NUT) durumunu gösteren widget. Veri, uygulama (NutProvider.refresh())
/// veya uygulama kapalıyken arka plan bildirim servisi tarafından
/// "ups_units_json" anahtarına yazılır. En fazla 4 UPS satırı gösterilir.
///
/// Widget 3 farklı detay seviyesi arasında geçiş yapar (küçük/orta/büyük) —
/// büyük boyutta sıcaklık, gerilim, yük (load) ve durum (pilde/şebekede)
/// gibi ek parametreler görünür. Geçiş, onAppWidgetOptionsChanged'de
/// widget'ın MIN_WIDTH/MIN_HEIGHT seçeneklerine bakılarak elle yapılıyor —
/// bazı launcher'lar (ör. Samsung One UI) Android 12'nin
/// RemoteViews(Map<SizeF,...>) API'sini resize sırasında güvenilir şekilde
/// tetiklemiyor.
///
/// Her satırdaki "UPS kutusu" ikonu pil/şebeke durumuna göre renklendirilir
/// (yeşil=şebekede, turuncu=pilde) — sabit bir nokta yerine gerçek bir cihaz
/// simgesi kullanılır.
class UpsWidgetProvider : HomeWidgetProvider() {
    companion object {
        private const val MAX_ROWS = 4
        private val ROW_IDS = intArrayOf(R.id.ups_row_1, R.id.ups_row_2, R.id.ups_row_3, R.id.ups_row_4)
        private val ICON_IDS = intArrayOf(R.id.ups_dot_1, R.id.ups_dot_2, R.id.ups_dot_3, R.id.ups_dot_4)
        private val NAME_IDS = intArrayOf(R.id.ups_name_1, R.id.ups_name_2, R.id.ups_name_3, R.id.ups_name_4)
        private val CHARGE_IDS = intArrayOf(R.id.ups_charge_1, R.id.ups_charge_2, R.id.ups_charge_3, R.id.ups_charge_4)
        private val BAR_IDS = intArrayOf(R.id.ups_bar_1, R.id.ups_bar_2, R.id.ups_bar_3, R.id.ups_bar_4)
        private val RUNTIME_IDS = intArrayOf(R.id.ups_runtime_1, R.id.ups_runtime_2, R.id.ups_runtime_3, R.id.ups_runtime_4)
        private val DETAIL_IDS = intArrayOf(R.id.ups_detail_1, R.id.ups_detail_2, R.id.ups_detail_3, R.id.ups_detail_4)

        private const val COLOR_ON_BATTERY = 0xFFD4893A.toInt()
        private const val COLOR_ON_MAINS = 0xFF3DB885.toInt()
        private const val COLOR_UNREACHABLE = 0xFF8A8A8E.toInt()
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

        val raw = HomeWidgetPlugin.getData(context).getString("ups_units_json", null)

        // Sadece toplam widget boyutuna bakmak yetmiyor: 1 UPS ile 4 UPS aynı
        // alana çok farklı şekilde sığar. Satır başına düşen gerçek alan
        // hesaplanıp ona göre karar veriliyor.
        val rowCount = try {
            if (raw != null) {
                (JSONObject(raw).optJSONArray("units")?.length() ?: 0).coerceIn(1, MAX_ROWS)
            } else 1
        } catch (e: Exception) {
            1
        }
        val perRowLarge = (height - 65) / rowCount
        val perRowMedium = (height - 50) / rowCount

        val detailed = width >= 200 && perRowLarge >= 85
        val compact = width < 130 || (!detailed && perRowMedium < 58)
        val layoutId = when {
            detailed -> R.layout.widget_ups_large
            compact -> R.layout.widget_ups_small
            else -> R.layout.widget_ups
        }

        val views = buildViews(context, layoutId, raw, detailed = detailed)
        try {
            val updatedAt = HomeWidgetPlugin.getData(context).getLong("ups_updated_at", 0L)
            views.setTextViewText(R.id.ups_updated_text, WidgetFormat.relativeUpdatedAt(updatedAt))
        } catch (_: Exception) {
        }
        views.setOnClickPendingIntent(
            R.id.widget_root_ups,
            HomeWidgetLaunchIntent.getActivity(context, MainActivity::class.java),
        )
        appWidgetManager.updateAppWidget(widgetId, views)
    }

    private fun buildViews(context: Context, layoutId: Int, raw: String?, detailed: Boolean): RemoteViews {
        val views = RemoteViews(context.packageName, layoutId)

        // AdGuard/Proxmox'la aynı 3-durumlu ayrım — bkz. ProxmoxWidgetProvider.
        if (raw == null) {
            views.setViewVisibility(R.id.ups_content, View.GONE)
            views.setViewVisibility(R.id.ups_empty_text, View.VISIBLE)
            views.setTextViewText(R.id.ups_empty_text, "Henüz yapılandırılmadı")
            return views
        }

        val units: JSONArray
        val configured: Boolean
        val deviceOffline: Boolean
        try {
            val obj = JSONObject(raw)
            configured = obj.optBoolean("configured", false)
            // Birim-özel "reachable:false"tan bilinçli olarak ayrı — cihazın
            // kendi interneti yokken background_service.dart bunu enjekte
            // ediyor (bkz. _markWidgetsDeviceOffline), hangi UPS'in gerçekten
            // ulaşılamaz olduğunu BİLMİYORUZ, sadece bilemediğimizi
            // gösteriyoruz.
            deviceOffline = obj.optBoolean("deviceOffline", false)
            units = obj.optJSONArray("units") ?: JSONArray()
        } catch (e: Exception) {
            views.setViewVisibility(R.id.ups_content, View.GONE)
            views.setViewVisibility(R.id.ups_empty_text, View.VISIBLE)
            views.setTextViewText(R.id.ups_empty_text, "Veri okunamadı")
            return views
        }

        if (!configured) {
            views.setViewVisibility(R.id.ups_content, View.GONE)
            views.setViewVisibility(R.id.ups_empty_text, View.VISIBLE)
            views.setTextViewText(R.id.ups_empty_text, "Henüz yapılandırılmadı")
            return views
        }

        if (units.length() == 0) {
            views.setViewVisibility(R.id.ups_content, View.GONE)
            views.setViewVisibility(R.id.ups_empty_text, View.VISIBLE)
            views.setTextViewText(R.id.ups_empty_text, "Bağlantı yok")
            try {
                views.setViewVisibility(R.id.ups_overflow_text, View.GONE)
            } catch (_: Exception) {
            }
            return views
        }

        views.setViewVisibility(R.id.ups_content, View.VISIBLE)
        views.setViewVisibility(R.id.ups_empty_text, View.GONE)

        val shown = minOf(units.length(), MAX_ROWS)
        for (i in 0 until MAX_ROWS) {
            if (i >= shown) {
                try {
                    views.setViewVisibility(ROW_IDS[i], View.GONE)
                } catch (_: Exception) {
                }
                continue
            }
            val unit = units.getJSONObject(i)
            val reachable = unit.optBoolean("reachable", true)
            val onBattery = unit.optBoolean("onBattery", false)
            val charge = unit.optInt("charge", 0)
            val runtimeLabel = unit.optString("runtimeLabel", "-")
            val load = unit.optInt("load", 0)
            val temperature = unit.optInt("temperature", 0)
            val voltage = unit.optDouble("voltage", 0.0)
            val statusLabel = unit.optString("statusLabel", "-")

            try {
                views.setViewVisibility(ROW_IDS[i], View.VISIBLE)
                views.setTextViewText(NAME_IDS[i], unit.optString("name", "-"))
                views.setInt(
                    ICON_IDS[i],
                    "setColorFilter",
                    if (!reachable || deviceOffline) COLOR_UNREACHABLE else if (onBattery) COLOR_ON_BATTERY else COLOR_ON_MAINS,
                )
                // Ulaşılamıyorsa şarj/bar son bilinen değeri gösterir (bkz.
                // background_service.dart'taki ups_bg_last_charge_ kalıcılığı)
                // ama satır metni bunun BAYAT olduğunu açıkça söyler — sessizce
                // güncelmiş gibi görünmesin diye. deviceOffline, !reachable'dan
                // AYRI bir sebep — hangi UPS'in gerçekten ulaşılamaz olduğunu
                // bilmiyoruz, sadece cihazın interneti olmadığını biliyoruz.
                views.setTextViewText(CHARGE_IDS[i], "%$charge")
                views.setProgressBar(BAR_IDS[i], 100, charge.coerceIn(0, 100), false)
                trySetText(
                    views,
                    RUNTIME_IDS[i],
                    when {
                        deviceOffline -> "Bağlantı yok"
                        !reachable -> "Bağlantı yok"
                        onBattery && runtimeLabel != "-" -> "Pilde · kalan: $runtimeLabel"
                        else -> statusLabel
                    },
                )
                if (detailed) {
                    val detailText = if (deviceOffline) {
                        "Cihazınızın interneti yok — son bilinen değerler gösteriliyor"
                    } else if (!reachable) {
                        "Sunucuya ulaşılamıyor — son bilinen değerler gösteriliyor"
                    } else {
                        val voltageText = if (voltage > 0) String.format(Locale.US, "%.1fV", voltage) else ""
                        val tempText = if (temperature > 0) "$temperature°C" else ""
                        listOf(statusLabel, "Yük %$load", voltageText, tempText)
                            .filter { it.isNotEmpty() }.joinToString(" · ")
                    }
                    trySetText(views, DETAIL_IDS[i], detailText)
                }
            } catch (_: Exception) {
            }
        }

        val remaining = units.length() - shown
        try {
            if (remaining > 0) {
                views.setViewVisibility(R.id.ups_overflow_text, View.VISIBLE)
                views.setTextViewText(R.id.ups_overflow_text, "+$remaining UPS daha")
            } else {
                views.setViewVisibility(R.id.ups_overflow_text, View.GONE)
            }
        } catch (_: Exception) {
        }

        return views
    }

    private fun trySetText(views: RemoteViews, id: Int, text: String) {
        try {
            views.setTextViewText(id, text)
        } catch (_: Exception) {
        }
    }
}
