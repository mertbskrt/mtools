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

/// Wake-on-LAN widget'ı — kayıtlı cihazların kısa bir özetini ve her birine
/// tek dokunuşla "Uyandır" butonunu gösterir. Veri, uygulama tarafından
/// (wol_screen.dart, cihaz listesi her değiştiğinde) "wol_devices_json"
/// anahtarına yazılır.
///
/// Diğer üç widget'la aynı responsive/yapılandırma deseni: appWidgetId
/// bazlı seçim (`WolWidgetConfigureActivity`, `ProxmoxWidgetConfigureActivity`
/// ile aynı şablon) + genişlik/yükseklik eşiğine göre 3 boyut varyantı.
///
/// Buton gönderimi `WolWidgetActionReceiver`'a düşer — Flutter engine hiç
/// açılmadan, native Kotlin'de UDP magic packet gönderilir (SSH-relay
/// yöntemi widget'tan desteklenmiyor, dartssh2/ProxmoxProvider'a bağımlı).
class WolWidgetProvider : HomeWidgetProvider() {
    companion object {
        const val MAX_ROWS = 4
        const val COOLDOWN_MS = 4000L

        private val ROW_IDS = intArrayOf(R.id.wol_row_1, R.id.wol_row_2, R.id.wol_row_3, R.id.wol_row_4)
        private val NAME_IDS = intArrayOf(R.id.wol_name_1, R.id.wol_name_2, R.id.wol_name_3, R.id.wol_name_4)
        private val BUTTON_IDS = intArrayOf(R.id.wol_button_1, R.id.wol_button_2, R.id.wol_button_3, R.id.wol_button_4)
        private val DESC_IDS = intArrayOf(R.id.wol_desc_1, R.id.wol_desc_2, R.id.wol_desc_3, R.id.wol_desc_4)

        fun selectionKey(appWidgetId: Int) = "wol_widget_devices_$appWidgetId"
        fun cooldownKey(appWidgetId: Int, mac: String) = "wol_cooldown_${appWidgetId}_$mac"
        /// Paket GERÇEKTEN gönderilemediğinde (ör. NetworkOnMainThreadException,
        /// ya da gerçek bir IO hatası) bu anahtar cooldownKey YERİNE set edilir
        /// — "Gönderildi ✓" yalanı söylemek yerine dürüst bir "Gönderilemedi"
        /// göstergesi, ve kilitlemiyor (hiçbir paket gitmediği için tekrar
        /// denemeyi engellemenin bir faydası yok).
        fun failedKey(appWidgetId: Int, mac: String) = "wol_failed_${appWidgetId}_$mac"

        /// ProxmoxWidgetProvider.configurePendingIntent ile aynı gerekçe:
        /// "uzun bas → Yapılandır" bazı launcher'larda widget ilk eklendikten
        /// sonra bir daha tetiklenmiyor — bu, garantili bir alternatif.
        private fun configurePendingIntent(context: Context, widgetId: Int): PendingIntent {
            val intent = Intent(context, WolWidgetConfigureActivity::class.java)
                .putExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, widgetId)
            return PendingIntent.getActivity(
                context, widgetId, intent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
            )
        }

        /// Hem onUpdate/onAppWidgetOptionsChanged hem de ActionReceiver'ın
        /// gönderim sonrası anlık + gecikmeli (cooldown bitince) yenilemesi
        /// için companion'a alındı — ProxmoxWidgetProvider ile aynı desen.
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
            val raw = prefs.getString("wol_devices_json", null)
            val selectionRaw = prefs.getString(selectionKey(widgetId), null)
            val devices = filterDevices(raw, selectionRaw)

            val rowCount = devices.length().coerceIn(1, MAX_ROWS)
            val perRowLarge = (height - 60) / rowCount
            val perRowMedium = (height - 50) / rowCount
            // ProxmoxWidgetProvider ile aynı eşikler (yükseklik-tabanlı
            // compact geri düşüşü dahil) — dört widget tutarlı boyutlarda
            // geçiş yapsın diye (önceki 150dp/70/sadece-genişlik değerlerinin
            // gerekçesi yoktu, Proxmox/UPS'ten sapıyordu).
            val detailed = width >= 200 && perRowLarge >= 80
            val compact = width < 130 || (!detailed && perRowMedium < 55)
            val layoutId = when {
                detailed -> R.layout.widget_wol_large
                compact -> R.layout.widget_wol_small
                else -> R.layout.widget_wol
            }

            val views = buildViews(context, layoutId, devices, widgetId, compact, detailed)
            views.setOnClickPendingIntent(
                R.id.widget_root_wol,
                HomeWidgetLaunchIntent.getActivity(context, MainActivity::class.java),
            )
            views.setOnClickPendingIntent(
                R.id.wol_widget_settings,
                configurePendingIntent(context, widgetId),
            )
            appWidgetManager.updateAppWidget(widgetId, views)
        }

        /// "wol_devices_json"taki tüm cihazları, bu widget örneğinin
        /// appWidgetId-bazlı seçimine göre filtreler. Seçim kaydı yoksa
        /// (henüz yapılandırılmamış) hepsi döner — geriye dönük uyumlu.
        private fun filterDevices(raw: String?, selectionRaw: String?): JSONArray {
            val all = try {
                if (raw != null) JSONArray(raw) else JSONArray()
            } catch (_: Exception) {
                JSONArray()
            }
            val selected: Set<String>? = selectionRaw?.let {
                runCatching {
                    val arr = JSONArray(it)
                    (0 until arr.length()).map { i -> arr.getString(i) }.toSet()
                }.getOrNull()
            }
            if (selected == null) return all
            val filtered = JSONArray()
            for (i in 0 until all.length()) {
                val d = all.getJSONObject(i)
                if (selected.contains(d.optString("name", ""))) filtered.put(d)
            }
            return filtered
        }

        private fun buildViews(
            context: Context,
            layoutId: Int,
            devices: JSONArray,
            widgetId: Int,
            compact: Boolean,
            detailed: Boolean,
        ): RemoteViews {
            val views = RemoteViews(context.packageName, layoutId)
            val prefs = HomeWidgetPlugin.getData(context)

            if (devices.length() == 0) {
                views.setViewVisibility(R.id.wol_content, View.GONE)
                views.setViewVisibility(R.id.wol_empty_text, View.VISIBLE)
                return views
            }

            views.setViewVisibility(R.id.wol_content, View.VISIBLE)
            views.setViewVisibility(R.id.wol_empty_text, View.GONE)

            if (compact) {
                trySetText(views, R.id.wol_summary_text, "${devices.length()} cihaz")
                val allIntent = WolWidgetActionReceiver.wakeAllPendingIntent(context, widgetId)
                views.setOnClickPendingIntent(R.id.wol_wake_all_button, allIntent)
                return views
            }

            trySetText(views, R.id.wol_summary_text, "Wake on LAN · ${devices.length()} cihaz")
            try {
                val updatedAt = prefs.getLong("wol_devices_updated_at", 0L)
                views.setTextViewText(R.id.wol_updated_text, WidgetFormat.relativeUpdatedAt(updatedAt))
            } catch (_: Exception) {
            }

            val now = System.currentTimeMillis()
            val shown = minOf(devices.length(), MAX_ROWS)
            for (i in 0 until MAX_ROWS) {
                if (i >= shown) {
                    try {
                        views.setViewVisibility(ROW_IDS[i], View.GONE)
                    } catch (_: Exception) {
                    }
                    continue
                }
                val device = devices.getJSONObject(i)
                val name = device.optString("name", "-")
                val mac = device.optString("mac", "")
                val description = device.optString("description", "")

                try {
                    views.setViewVisibility(ROW_IDS[i], View.VISIBLE)
                    views.setTextViewText(NAME_IDS[i], name)
                    if (detailed) {
                        trySetText(views, DESC_IDS[i], description)
                    }

                    val cooldownUntil = prefs.getLong(cooldownKey(widgetId, mac), 0L)
                    val failedUntil = prefs.getLong(failedKey(widgetId, mac), 0L)
                    val sending = now < cooldownUntil
                    val failed = !sending && now < failedUntil

                    when {
                        sending -> {
                            views.setTextViewText(BUTTON_IDS[i], "Gönderildi ✓")
                            views.setInt(BUTTON_IDS[i], "setBackgroundResource", R.drawable.widget_wol_button_sent_bg)
                            // Cooldown sürerken bilinçli olarak PendingIntent
                            // atanmıyor — buton bu render için tıklanamaz
                            // kalır (art arda gereksiz paket gönderimini
                            // önler). ActionReceiver de aynı kontrolü ayrıca
                            // yapıyor (asıl güvence, olası eski render'a
                            // rağmen çift korumalı).
                        }
                        failed -> {
                            // Paket GERÇEKTEN gitmediği için (bkz. failedKey)
                            // kilitlemiyoruz — buton tıklanabilir kalıyor,
                            // kullanıcı hemen tekrar deneyebilir.
                            views.setTextViewText(BUTTON_IDS[i], "Gönderilemedi")
                            views.setInt(BUTTON_IDS[i], "setBackgroundResource", R.drawable.widget_wol_button_failed_bg)
                            views.setOnClickPendingIntent(
                                BUTTON_IDS[i],
                                WolWidgetActionReceiver.wakePendingIntent(context, widgetId, i, mac),
                            )
                        }
                        else -> {
                            views.setTextViewText(BUTTON_IDS[i], "Uyandır")
                            views.setInt(BUTTON_IDS[i], "setBackgroundResource", R.drawable.widget_wol_button_bg)
                            views.setOnClickPendingIntent(
                                BUTTON_IDS[i],
                                WolWidgetActionReceiver.wakePendingIntent(context, widgetId, i, mac),
                            )
                        }
                    }
                } catch (_: Exception) {
                }
            }

            val remaining = devices.length() - shown
            try {
                if (remaining > 0) {
                    views.setViewVisibility(R.id.wol_overflow_text, View.VISIBLE)
                    views.setTextViewText(R.id.wol_overflow_text, "+$remaining cihaz daha")
                } else {
                    views.setViewVisibility(R.id.wol_overflow_text, View.GONE)
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

    /// Proxmox'takiyle aynı: widget silinince o örneğin seçim kaydı
    /// temizlenir (cooldown anahtarları küçük/geçici olduğu için ayrıca
    /// süpürülmüyor — 4sn sonra zaten anlamsızlaşıyorlar).
    override fun onDeleted(context: Context, appWidgetIds: IntArray) {
        super.onDeleted(context, appWidgetIds)
        val editor = HomeWidgetPlugin.getData(context).edit()
        for (id in appWidgetIds) {
            editor.remove(selectionKey(id))
        }
        editor.apply()
    }
}
