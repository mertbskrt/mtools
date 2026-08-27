package com.example.mtools_v2

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.Intent
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
///
/// Proxmox/WOL widget'larıyla aynı desen: `UpsWidgetConfigureActivity`
/// üzerinden her widget örneği hangi UPS birimlerinin görüneceğini seçebilir
/// (bkz. selectionKey) — birden fazla NUT sunucusu/birimi olan kurulumlarda
/// aynı widget'tan birden fazla eklenip her birine farklı bir seçim atanabilir.
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

        /// Her widget örneğinin (appWidgetId) kendi UPS birimi seçimi bu
        /// anahtar altında tutulur — bkz. UpsWidgetConfigureActivity.
        fun selectionKey(appWidgetId: Int) = "ups_widget_units_$appWidgetId"

        private fun configurePendingIntent(context: Context, widgetId: Int): PendingIntent {
            val intent = Intent(context, UpsWidgetConfigureActivity::class.java)
                .putExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, widgetId)
            return PendingIntent.getActivity(
                context, widgetId, intent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
            )
        }

        fun render(
            context: Context,
            appWidgetManager: AppWidgetManager,
            widgetId: Int,
            options: Bundle? = null,
        ) {
            val opts = options ?: appWidgetManager.getAppWidgetOptions(widgetId)
            val width = opts.getInt(AppWidgetManager.OPTION_APPWIDGET_MIN_WIDTH, 110)
            val height = opts.getInt(AppWidgetManager.OPTION_APPWIDGET_MIN_HEIGHT, 110)

            val prefs = HomeWidgetPlugin.getData(context)
            val raw = prefs.getString("ups_units_json", null)
            val selectionRaw = prefs.getString(selectionKey(widgetId), null)

            // Sadece toplam widget boyutuna bakmak yetmiyor: 1 UPS ile 4 UPS
            // aynı alana çok farklı şekilde sığar. Satır başına düşen gerçek
            // alan hesaplanıp ona göre karar veriliyor — seçime göre
            // filtrelenmiş sayı üzerinden (bkz. buildViews'taki filtreleme).
            val rowCount = try {
                val total = if (raw != null) JSONObject(raw).optJSONArray("units")?.length() ?: 0 else 0
                val selectedCount = selectionRaw?.let { runCatching { JSONArray(it).length() }.getOrNull() }
                (selectedCount ?: total).coerceIn(1, MAX_ROWS)
            } catch (e: Exception) {
                1
            }
            val perRowLarge = (height - 65) / rowCount
            val perRowMedium = (height - 50) / rowCount

            val detailed = width >= 200 && perRowLarge >= 85
            // Satır sayısı arttıkça (birden fazla UPS birimi) tek bir eşik
            // aşılınca TÜM widget'ın sadece BİRİNCİ birimi gösterip
            // diğerlerini iz bırakmadan kaybetmesi yerine (eski davranış),
            // önce satırların ikincil öğeleri küçültülüyor; tek-birim moduna
            // düşmek gerçekten hiçbir satırın sığmayacağı aşırı durumlar için.
            val compact = width < 130 || (!detailed && perRowMedium < 22)
            val richDetail = !compact && (detailed || perRowMedium >= 66)
            val layoutId = when {
                detailed -> R.layout.widget_ups_large
                compact -> R.layout.widget_ups_small
                else -> R.layout.widget_ups
            }

            val views = buildViews(
                context, layoutId, raw, selectionRaw,
                detailed = detailed, richDetail = richDetail, perRowHeight = perRowMedium,
            )
            try {
                val updatedAt = prefs.getLong("ups_updated_at", 0L)
                views.setTextViewText(R.id.ups_updated_text, WidgetFormat.relativeUpdatedAt(updatedAt))
            } catch (_: Exception) {
            }
            views.setOnClickPendingIntent(
                R.id.widget_root_ups,
                HomeWidgetLaunchIntent.getActivity(context, MainActivity::class.java),
            )
            try {
                views.setOnClickPendingIntent(
                    R.id.ups_widget_settings,
                    configurePendingIntent(context, widgetId),
                )
            } catch (_: Exception) {
            }
            appWidgetManager.updateAppWidget(widgetId, views)
        }

        private fun buildViews(
            context: Context,
            layoutId: Int,
            raw: String?,
            selectionRaw: String?,
            detailed: Boolean,
            richDetail: Boolean = false,
            perRowHeight: Int = Int.MAX_VALUE,
        ): RemoteViews {
            val views = RemoteViews(context.packageName, layoutId)

            // AdGuard/Proxmox'la aynı 3-durumlu ayrım — bkz. ProxmoxWidgetProvider.
            if (raw == null) {
                views.setViewVisibility(R.id.ups_content, View.GONE)
                views.setViewVisibility(R.id.ups_empty_text, View.VISIBLE)
                views.setTextViewText(R.id.ups_empty_text, "Henüz yapılandırılmadı")
                return views
            }

            val allUnits: JSONArray
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
                allUnits = obj.optJSONArray("units") ?: JSONArray()
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

            // Bu widget örneği için bir seçim kaydedilmişse sadece seçili
            // birimler gösterilir — seçim yoksa (henüz yapılandırılmamış eski
            // widget örneği) mevcut davranış (hepsini göster) korunur.
            val selectedNames: Set<String>? = selectionRaw?.let {
                runCatching {
                    val arr = JSONArray(it)
                    (0 until arr.length()).map { i -> arr.getString(i) }.toSet()
                }.getOrNull()
            }
            val units = if (selectedNames != null) {
                val filtered = JSONArray()
                for (i in 0 until allUnits.length()) {
                    val unit = allUnits.getJSONObject(i)
                    if (selectedNames.contains(unit.optString("name", ""))) filtered.put(unit)
                }
                filtered
            } else {
                allUnits
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
                val inputVoltage = unit.optDouble("inputVoltage", 0.0)
                val outputVoltage = unit.optDouble("outputVoltage", 0.0)
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
                    // widget_ups_large.xml'de ups_runtime_N hiç yok (bkz.
                    // DETAIL_IDS bu bilgiyi zaten kapsıyor) — detailed'da bu
                    // çağrı zaten sessizce no-op oluyordu, netlik için atlanıyor.
                    if (!detailed) {
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
                    }
                    val inVText = if (inputVoltage > 0) "Giriş ${fmtVolt(inputVoltage)}V" else ""
                    val outVText = if (outputVoltage > 0) "Çıkış ${fmtVolt(outputVoltage)}V" else ""
                    val corePart = listOf("Yük %$load", inVText, outVText)
                        .filter { it.isNotEmpty() }.joinToString(" · ")

                    if (detailed) {
                        val detailText = if (deviceOffline) {
                            "Cihazınızın interneti yok — son bilinen değerler gösteriliyor"
                        } else if (!reachable) {
                            "Sunucuya ulaşılamıyor — son bilinen değerler gösteriliyor"
                        } else {
                            val runtimePart =
                                if (onBattery && runtimeLabel != "-") "kalan: $runtimeLabel" else ""
                            val tempPart = if (temperature > 0) "$temperature°C" else ""
                            listOf(statusLabel, corePart, runtimePart, tempPart)
                                .filter { it.isNotEmpty() }.joinToString(" · ")
                        }
                        trySetText(views, DETAIL_IDS[i], detailText)
                    } else if (richDetail) {
                        val detailText = when {
                            deviceOffline -> "Cihazınızın interneti yok"
                            !reachable -> "Sunucuya ulaşılamıyor"
                            else -> corePart
                        }
                        views.setViewVisibility(DETAIL_IDS[i], View.VISIBLE)
                        trySetText(views, DETAIL_IDS[i], detailText)
                    } else {
                        views.setViewVisibility(DETAIL_IDS[i], View.GONE)
                    }
                    // widget_ups.xml'de (orta layout) satır sayısı arttıkça her
                    // satırın payına düşen yükseklik daralır — ProxmoxWidgetProvider'daki
                    // aynı düzeltme: önce ilerleme çubuğu, sonra iç boşluk küçültülüyor.
                    if (!detailed && layoutId != R.layout.widget_ups_small) {
                        if (perRowHeight < 55) {
                            views.setViewVisibility(BAR_IDS[i], View.GONE)
                        }
                        if (perRowHeight < 45) {
                            views.setViewPadding(ROW_IDS[i], dp(context, 6), dp(context, 6), dp(context, 6), dp(context, 6))
                        }
                    }
                } catch (_: Exception) {
                }
            }

            // Kompakt (small) layout'ta SADECE ilk birim görsel olarak var —
            // ROW_IDS[1..3] o layout'ta hiç bulunmuyor (yukarıdaki try/catch
            // sessizce yutuyor). Bu yüzden "kaç birim daha var" hesabı `shown`
            // değil, o modda gerçekten çizilen satır sayısına (1) göre yapılmalı
            // — aksi halde 2-3 UPS'li bir kurulumda diğer birimler hiçbir iz
            // bırakmadan kaybolurdu.
            val visuallyShown = if (layoutId == R.layout.widget_ups_small) 1 else shown
            val remaining = units.length() - visuallyShown
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

        private fun fmtVolt(v: Double): String = String.format(Locale.US, "%.1f", v)

        private fun dp(context: Context, value: Int): Int =
            (value * context.resources.displayMetrics.density).toInt()
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

    /// Widget örneği ana ekrandan kaldırılınca, o örneğe ait UPS seçimi de
    /// temizlenir — bkz. ProxmoxWidgetProvider.onDeleted'daki aynı gerekçe.
    override fun onDeleted(context: Context, appWidgetIds: IntArray) {
        super.onDeleted(context, appWidgetIds)
        val editor = HomeWidgetPlugin.getData(context).edit()
        for (id in appWidgetIds) {
            editor.remove(selectionKey(id))
        }
        editor.apply()
    }
}
