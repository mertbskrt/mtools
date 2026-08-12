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
///
/// Widget eklenirken (ya da uzun basılıp "Yapılandır" denince) açılan
/// `ProxmoxWidgetConfigureActivity`, kullanıcının HANGİ node'ların bu widget
/// örneğinde görüneceğini seçmesini sağlar — her appWidgetId kendi seçimini
/// ayrı tutar (bkz. `selectionKey`), aynı widget'tan birden fazla eklenip
/// her birine farklı bir node seti atanabilir.
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
        // UPS'teki COLOR_UNREACHABLE ile aynı değer — "cihazın interneti
        // yok" durumu üç widget'ta da aynı nötr griyle gösterilir.
        private const val COLOR_UNREACHABLE = 0xFF8A8A8E.toInt()

        /// Her widget örneğinin (appWidgetId) kendi node seçimi bu anahtar
        /// altında tutulur — bkz. ProxmoxWidgetConfigureActivity.
        fun selectionKey(appWidgetId: Int) = "proxmox_widget_nodes_$appWidgetId"

        /// "Uzun bas → Yapılandır" bazı launcher'larda (uzun-basma menüsünde
        /// widget'a özel bir "Yapılandır" seçeneği sunmayan/APPWIDGET_CONFIGURE
        /// action'ını göndermeyen launcher'lar) widget ilk eklendikten SONRA
        /// hiç tetiklenmiyor — bu, android:configure'a bağımlı kalmadan
        /// ConfigureActivity'yi doğrudan bu appWidgetId ile açan garantili
        /// bir alternatif. Açık (explicit) Intent olduğu için intent-filter
        /// eşleşmesine ihtiyaç yok.
        private fun configurePendingIntent(context: Context, widgetId: Int): PendingIntent {
            val intent = Intent(context, ProxmoxWidgetConfigureActivity::class.java)
                .putExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, widgetId)
            return PendingIntent.getActivity(
                context, widgetId, intent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
            )
        }

        /// Hem onUpdate/onAppWidgetOptionsChanged hem de yapılandırma
        /// ekranı kaydettikten sonra anında yenileme için companion'a
        /// taşındı — Activity de aynı render mantığını çağırabiliyor.
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
            val raw = prefs.getString("proxmox_nodes_json", null)
            val selectionRaw = prefs.getString(selectionKey(widgetId), null)

            // Sadece toplam widget boyutuna bakmak yetmiyor: 1 node ile 4 node
            // aynı alana çok farklı şekilde sığar. Satır başına düşen gerçek
            // alan hesaplanıp ona göre karar veriliyor — aksi halde örn. 3 node
            // küçük bir widget'a sıkıştırılıp yazılar üst üste biniyordu.
            // Not: satır sayısı hesabı, boyut kararından ÖNCE seçime göre
            // filtrelenmiş listeye göre yapılmalı — bkz. buildViews'taki
            // filtreleme, oradaki `nodes.length()` zaten filtrelenmiş sayı.
            val rowCount = try {
                val total = if (raw != null) JSONObject(raw).optJSONArray("nodes")?.length() ?: 0 else 0
                val selectedCount = selectionRaw?.let { runCatching { JSONArray(it).length() }.getOrNull() }
                (selectedCount ?: total).coerceIn(1, MAX_ROWS)
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
            val views = buildViews(
                context, layoutId, raw, selectionRaw,
                detailed = detailed, compactSummary = compact,
            )
            try {
                val updatedAt = prefs.getLong("proxmox_updated_at", 0L)
                views.setTextViewText(R.id.proxmox_updated_text, WidgetFormat.relativeUpdatedAt(updatedAt))
            } catch (_: Exception) {
            }
            views.setOnClickPendingIntent(
                R.id.widget_root_proxmox,
                HomeWidgetLaunchIntent.getActivity(context, MainActivity::class.java),
            )
            views.setOnClickPendingIntent(
                R.id.proxmox_widget_settings,
                configurePendingIntent(context, widgetId),
            )
            appWidgetManager.updateAppWidget(widgetId, views)
        }

        private fun buildViews(
            context: Context,
            layoutId: Int,
            raw: String?,
            selectionRaw: String?,
            detailed: Boolean,
            compactSummary: Boolean,
        ): RemoteViews {
            val views = RemoteViews(context.packageName, layoutId)

            // AdGuard'daki aynı 3-durumlu ayrım: "hiç yapılandırılmadı" (raw
            // yok ya da configured:false), "yapılandırıldı ama veri yok/
            // erişilemiyor" (configured:true, nodes boş), ve JSON bozuksa
            // "veri okunamadı" — üçü de tek bir jenerik "Bağlantı yok"
            // yerine ayrı ayrı mesaj veriyor.
            if (raw == null) {
                views.setViewVisibility(R.id.proxmox_content, View.GONE)
                views.setViewVisibility(R.id.proxmox_empty_text, View.VISIBLE)
                views.setTextViewText(R.id.proxmox_empty_text, "Henüz yapılandırılmadı")
                return views
            }

            val allNodes: JSONArray
            val configured: Boolean
            val deviceOffline: Boolean
            try {
                val obj = JSONObject(raw)
                configured = obj.optBoolean("configured", false)
                // Servis-özel "ulaşılamıyor" (online:false) durumundan
                // bilinçli olarak ayrı bir sinyal — cihazın kendi interneti
                // yokken background_service.dart bunu enjekte ediyor (bkz.
                // _markWidgetsDeviceOffline), hangi node'un gerçekten
                // çevrimdışı olduğunu BİLMİYORUZ, sadece bilemediğimizi
                // gösteriyoruz.
                deviceOffline = obj.optBoolean("deviceOffline", false)
                allNodes = obj.optJSONArray("nodes") ?: JSONArray()
            } catch (e: Exception) {
                views.setViewVisibility(R.id.proxmox_content, View.GONE)
                views.setViewVisibility(R.id.proxmox_empty_text, View.VISIBLE)
                views.setTextViewText(R.id.proxmox_empty_text, "Veri okunamadı")
                return views
            }

            if (!configured) {
                views.setViewVisibility(R.id.proxmox_content, View.GONE)
                views.setViewVisibility(R.id.proxmox_empty_text, View.VISIBLE)
                views.setTextViewText(R.id.proxmox_empty_text, "Henüz yapılandırılmadı")
                return views
            }

            // Bu widget örneği için bir seçim kaydedilmişse (yapılandırma
            // ekranından geçmiş), sadece seçili node'lar gösterilir — orijinal
            // API sırası korunur. Seçim yoksa (henüz yapılandırılmamış eski
            // widget örneği, ya da veri gelmeden önce "Tamam" denmişse)
            // mevcut davranış (hepsini göster) korunur — geriye dönük uyumlu.
            val selectedNames: Set<String>? = selectionRaw?.let {
                runCatching {
                    val arr = JSONArray(it)
                    (0 until arr.length()).map { i -> arr.getString(i) }.toSet()
                }.getOrNull()
            }
            val nodes = if (selectedNames != null) {
                val filtered = JSONArray()
                for (i in 0 until allNodes.length()) {
                    val node = allNodes.getJSONObject(i)
                    if (selectedNames.contains(node.optString("name", ""))) filtered.put(node)
                }
                filtered
            } else {
                allNodes
            }

            if (nodes.length() == 0) {
                views.setViewVisibility(R.id.proxmox_content, View.GONE)
                views.setViewVisibility(R.id.proxmox_empty_text, View.VISIBLE)
                views.setTextViewText(R.id.proxmox_empty_text, "Bağlantı yok")
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
                    views.setInt(
                        DOT_IDS[i],
                        "setColorFilter",
                        if (deviceOffline) COLOR_UNREACHABLE else if (online) COLOR_ONLINE else COLOR_OFFLINE,
                    )
                    views.setTextViewText(
                        STATS_IDS[i],
                        when {
                            deviceOffline -> "Cihazınızın interneti yok"
                            !online -> "Çevrimdışı"
                            detailed -> {
                                val tempPart = if (temp >= 0) " · $temp°C" else ""
                                "CPU %$cpu · RAM %$mem · Disk %$disk$tempPart"
                            }
                            else -> "CPU %$cpu · RAM %$mem"
                        },
                    )
                    views.setProgressBar(BAR_IDS[i], 100, if (online && !deviceOffline) cpu.coerceIn(0, 100) else 0, false)
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
                    when {
                        deviceOffline -> "Bağlantı yok"
                        compactSummary -> "$onlineCount/${nodes.length()}"
                        else -> "$onlineCount/${nodes.length()} çevrimiçi"
                    },
                )
            } catch (_: Exception) {
            }
            if (compactSummary) {
                try {
                    views.setInt(
                        DOT_IDS[0],
                        "setColorFilter",
                        if (deviceOffline) {
                            COLOR_UNREACHABLE
                        } else if (onlineCount == nodes.length()) {
                            COLOR_ONLINE
                        } else {
                            COLOR_PARTIAL
                        },
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

    /// Widget örneği ana ekrandan kaldırılınca, o örneğe ait node seçimi de
    /// temizlenir — aksi halde SharedPreferences'ta sonsuza dek birikirdi.
    /// Aynı widget daha sonra tekrar eklenince Android YENİ bir appWidgetId
    /// atar (eskisini asla yeniden kullanmaz), bu yüzden yeni örnek zaten bu
    /// eski kayıttan habersiz başlar — ama temizlik yine de doğru pratik.
    override fun onDeleted(context: Context, appWidgetIds: IntArray) {
        super.onDeleted(context, appWidgetIds)
        val editor = HomeWidgetPlugin.getData(context).edit()
        for (id in appWidgetIds) {
            editor.remove(selectionKey(id))
        }
        editor.apply()
    }
}
