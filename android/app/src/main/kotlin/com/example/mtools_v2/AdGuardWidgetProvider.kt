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
import org.json.JSONObject

/// AdGuard Home ana ekran widget'ı. Veri, uygulama tarafından
/// (AdGuardProvider.refresh() her çalıştığında) "adguard_stats_json"
/// anahtarına yazılır — bu sınıf sadece o veriyi okuyup çiziyor.
///
/// Widget 4 farklı detay seviyesi arasında geçiş yapar (küçük/orta/büyük/
/// çok büyük) — kullanıcı widget'ı büyüttükçe daha fazla istatistik görünür.
/// Bazı launcher'lar (ör. Samsung One UI) Android 12'nin
/// RemoteViews(Map<SizeF,...>) API'sini resize sırasında güvenilir şekilde
/// tetiklemediği için asıl geçiş mantığı onAppWidgetOptionsChanged'de,
/// widget'ın MIN_WIDTH/MIN_HEIGHT seçeneklerine bakılarak elle yapılıyor.
class AdGuardWidgetProvider : HomeWidgetProvider() {
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

        val layoutId = when {
            width >= 250 && height >= 250 -> R.layout.widget_adguard_xlarge
            width >= 180 && height >= 180 -> R.layout.widget_adguard_large
            width >= 140 && height >= 140 -> R.layout.widget_adguard
            else -> R.layout.widget_adguard_small
        }

        val data = HomeWidgetPlugin.getData(context)
        val raw = data.getString("adguard_stats_json", null)
        val views = buildViews(context, layoutId, raw)
        try {
            val updatedAt = data.getLong("adguard_updated_at", 0L)
            views.setTextViewText(R.id.adguard_updated_at, WidgetFormat.relativeUpdatedAt(updatedAt))
        } catch (_: Exception) {
        }
        views.setOnClickPendingIntent(
            R.id.widget_root_adguard,
            HomeWidgetLaunchIntent.getActivity(context, MainActivity::class.java),
        )
        appWidgetManager.updateAppWidget(widgetId, views)
    }

    private fun buildViews(context: Context, layoutId: Int, raw: String?): RemoteViews {
        val views = RemoteViews(context.packageName, layoutId)

        if (raw == null) {
            views.setViewVisibility(R.id.adguard_content, View.GONE)
            views.setViewVisibility(R.id.adguard_empty_text, View.VISIBLE)
            views.setTextViewText(R.id.adguard_empty_text, "Henüz yapılandırılmadı")
            return views
        }

        try {
            val data = JSONObject(raw)
            val configured = data.optBoolean("configured", false)
            val connected = data.optBoolean("connected", false)
            // connected:false'tan bilinçli olarak ayrı bir sebep — cihazın
            // kendi interneti yokken background_service.dart bunu enjekte
            // ediyor (bkz. _markWidgetsDeviceOffline). AdGuard zaten "bayat
            // sayı" göstermiyor (connected:false'ta hiç istatistik
            // taşınmıyor), bu yüzden aynı boş-durum mekanizması yeniden
            // kullanılıyor, sadece sebep metni değişiyor.
            val deviceOffline = data.optBoolean("deviceOffline", false)

            if (!configured || !connected || deviceOffline) {
                views.setViewVisibility(R.id.adguard_content, View.GONE)
                views.setViewVisibility(R.id.adguard_empty_text, View.VISIBLE)
                views.setTextViewText(
                    R.id.adguard_empty_text,
                    when {
                        !configured -> "Henüz yapılandırılmadı"
                        deviceOffline -> "Cihazınızın interneti yok"
                        else -> "Bağlantı yok"
                    },
                )
                return views
            }

            views.setViewVisibility(R.id.adguard_content, View.VISIBLE)
            views.setViewVisibility(R.id.adguard_empty_text, View.GONE)

            val isProtected = data.optBoolean("protected", true)
            val total = data.optInt("total", 0)
            val blockedPct = data.optInt("blockedPct", 0)
            val avgMs = data.optInt("avgMs", 0)
            val clients = data.optInt("clients", 0)
            val securityBlocked = data.optInt("securityBlocked", 0)
            val topClients = data.optJSONArray("topClients")

            views.setImageViewResource(
                R.id.adguard_status_dot,
                if (isProtected) R.drawable.widget_dot_success else R.drawable.widget_dot_error,
            )
            trySetText(views, R.id.adguard_status_text, if (isProtected) "Korumalı" else "Korumasız")
            trySetText(views, R.id.adguard_total_value, WidgetFormat.compactCount(total))
            trySetText(views, R.id.adguard_blocked_value, "%$blockedPct")
            trySetText(views, R.id.adguard_clients_value, clients.toString())
            trySetProgress(views, R.id.adguard_progress, blockedPct)
            trySetText(
                views,
                R.id.adguard_avg_text,
                if (avgMs > 0) "Ort. yanıt: ${avgMs}ms" else "",
            )
            trySetText(
                views,
                R.id.adguard_security_text,
                if (securityBlocked > 0) "Güvenlik filtreleri: ${WidgetFormat.compactCount(securityBlocked)} engel" else "",
            )

            val clientIds = intArrayOf(R.id.adguard_client_1, R.id.adguard_client_2, R.id.adguard_client_3)
            for (i in clientIds.indices) {
                val name = topClients?.optString(i, "") ?: ""
                trySetText(views, clientIds[i], if (name.isNotEmpty()) "• $name" else "")
            }
        } catch (e: Exception) {
            views.setViewVisibility(R.id.adguard_content, View.GONE)
            views.setViewVisibility(R.id.adguard_empty_text, View.VISIBLE)
            views.setTextViewText(R.id.adguard_empty_text, "Veri okunamadı")
        }

        return views
    }

    /// Bazı id'ler her boyut layout'unda mevcut olmadığı için (ör. küçük
    /// layout'ta istatistik ızgarası yok) RemoteViews çağrıları güvenli
    /// şekilde no-op yapılıyor; try/catch ek bir güvenlik katmanı.
    private fun trySetText(views: RemoteViews, id: Int, text: String) {
        try {
            views.setTextViewText(id, text)
        } catch (_: Exception) {
        }
    }

    private fun trySetProgress(views: RemoteViews, id: Int, value: Int) {
        try {
            views.setProgressBar(id, 100, value.coerceIn(0, 100), false)
        } catch (_: Exception) {
        }
    }
}
