package com.example.mtools_v2

import android.app.AlarmManager
import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.SystemClock
import android.util.Log
import es.antonborri.home_widget.HomeWidgetPlugin
import org.json.JSONArray
import java.net.DatagramPacket
import java.net.DatagramSocket
import java.net.InetAddress

/// WOL widget'ındaki "Uyandır"/"Hepsini Uyandır" butonlarının tıklanmasını
/// işler — Flutter engine hiç açılmadan, doğrudan native Kotlin'de UDP
/// magic packet gönderir.
///
/// Not: bu, wol_screen.dart'taki _sendUdpMagicPacket ile AYNI algoritmanın
/// Kotlin'e yeniden yazılmış hali — RemoteViews/widget bağlamından Dart
/// koduna erişilemediği için kod paylaşımı mümkün değil. Magic packet
/// formatı sabit bir protokol (102 byte: 6×0xFF + MAC×16) olduğu için bu
/// tekrarın gelecekte ayrışma riski düşük. SSH-relay yöntemi burada
/// DESTEKLENMİYOR (dartssh2/ProxmoxProvider'a bağımlı, native tarafta yok)
/// — 'ssh' yöntemli cihazlar için de widget yine de düz UDP magic packet
/// dener (bkz. WolWidgetProvider — hiçbir satır "Uygulamada Aç"a düşmez).
class WolWidgetActionReceiver : BroadcastReceiver() {
    companion object {
        private const val ACTION_WAKE_ONE = "com.example.mtools_v2.WOL_WAKE_ONE"
        private const val ACTION_WAKE_ALL = "com.example.mtools_v2.WOL_WAKE_ALL"
        private const val ACTION_REFRESH = "com.example.mtools_v2.WOL_REFRESH"

        private const val EXTRA_WIDGET_ID = "widgetId"
        private const val EXTRA_MAC = "mac"
        private const val EXTRA_BROADCAST_IP = "broadcastIp"
        private const val EXTRA_ROW = "row"

        fun wakePendingIntent(context: Context, widgetId: Int, row: Int, mac: String): PendingIntent {
            val broadcastIp = broadcastIpFor(context, mac)
            val intent = Intent(context, WolWidgetActionReceiver::class.java).apply {
                action = ACTION_WAKE_ONE
                putExtra(EXTRA_WIDGET_ID, widgetId)
                putExtra(EXTRA_MAC, mac)
                putExtra(EXTRA_BROADCAST_IP, broadcastIp)
            }
            // requestCode widgetId+mac'e özgü olmalı — aksi halde farklı
            // cihazların/widget örneklerinin PendingIntent'leri birbirinin
            // üzerine yazar (aynı extra'larla güncellenir).
            val requestCode = widgetId * 1000 + row
            return PendingIntent.getBroadcast(
                context, requestCode, intent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
            )
        }

        fun wakeAllPendingIntent(context: Context, widgetId: Int): PendingIntent {
            val intent = Intent(context, WolWidgetActionReceiver::class.java).apply {
                action = ACTION_WAKE_ALL
                putExtra(EXTRA_WIDGET_ID, widgetId)
            }
            return PendingIntent.getBroadcast(
                context, widgetId, intent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
            )
        }

        private fun broadcastIpFor(context: Context, mac: String): String {
            val raw = HomeWidgetPlugin.getData(context).getString("wol_devices_json", null) ?: return "255.255.255.255"
            return try {
                val arr = JSONArray(raw)
                for (i in 0 until arr.length()) {
                    val d = arr.getJSONObject(i)
                    if (d.optString("mac", "") == mac) {
                        return d.optString("broadcastIp", "255.255.255.255")
                    }
                }
                "255.255.255.255"
            } catch (_: Exception) {
                "255.255.255.255"
            }
        }

        /// wol_screen.dart _sendUdpMagicPacket ile birebir aynı format.
        private fun sendMagicPacket(mac: String, broadcastIp: String) {
            val cleanMac = mac.replace(Regex("[:\\-]"), "")
            require(cleanMac.length == 12) { "Geçersiz MAC adresi: $mac" }
            val macBytes = ByteArray(6) { i ->
                cleanMac.substring(i * 2, i * 2 + 2).toInt(16).toByte()
            }
            val packet = ByteArray(102)
            for (i in 0 until 6) packet[i] = 0xFF.toByte()
            for (i in 0 until 16) {
                for (j in 0 until 6) {
                    packet[6 + i * 6 + j] = macBytes[j]
                }
            }
            DatagramSocket().use { socket ->
                socket.broadcast = true
                val address = InetAddress.getByName(broadcastIp)
                socket.send(DatagramPacket(packet, packet.size, address, 9))
            }
        }

        /// Paket GERÇEKTEN gönderildiğinde çağrılır — cooldown kilidi başlar
        /// ("Gönderildi ✓", art arda tıklamaya kapalı).
        private fun markSent(context: Context, widgetId: Int, mac: String) {
            val prefs = HomeWidgetPlugin.getData(context)
            prefs.edit()
                .putLong(WolWidgetProvider.cooldownKey(widgetId, mac), System.currentTimeMillis() + WolWidgetProvider.COOLDOWN_MS)
                .remove(WolWidgetProvider.failedKey(widgetId, mac))
                .apply()
            scheduleRefresh(context, widgetId)
        }

        /// Paket GERÇEKTEN gönderilemediğinde (ör. NetworkOnMainThreadException,
        /// gerçek bir IO hatası) çağrılır — kilitlemez (hiçbir paket gitmediği
        /// için tekrar denemeyi engellemenin faydası yok), sadece geçici bir
        /// "Gönderilemedi" göstergesi.
        private fun markFailed(context: Context, widgetId: Int, mac: String) {
            val prefs = HomeWidgetPlugin.getData(context)
            prefs.edit()
                .putLong(WolWidgetProvider.failedKey(widgetId, mac), System.currentTimeMillis() + WolWidgetProvider.COOLDOWN_MS)
                .remove(WolWidgetProvider.cooldownKey(widgetId, mac))
                .apply()
            scheduleRefresh(context, widgetId)
        }

        /// Cooldown bitince widget'ı tekrar çizmek için — 4sn sonra widget
        /// provider'ının kendi ACTION_APPWIDGET_UPDATE akışını tetikliyoruz,
        /// ayrı bir "refresh" mantığı yazmaya gerek yok.
        private fun scheduleRefresh(context: Context, widgetId: Int) {
            val intent = Intent(context, WolWidgetProvider::class.java).apply {
                action = AppWidgetManager.ACTION_APPWIDGET_UPDATE
                putExtra(AppWidgetManager.EXTRA_APPWIDGET_IDS, intArrayOf(widgetId))
            }
            val pending = PendingIntent.getBroadcast(
                context, widgetId, intent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
            )
            val alarmManager = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
            val triggerAt = SystemClock.elapsedRealtime() + WolWidgetProvider.COOLDOWN_MS + 200
            try {
                alarmManager.setExactAndAllowWhileIdle(AlarmManager.ELAPSED_REALTIME_WAKEUP, triggerAt, pending)
            } catch (_: SecurityException) {
                // Bilinçli sessiz: exact alarm izni bir sebeple reddedilirse
                // widget bir sonraki doğal güncellemede (kullanıcı elle
                // yenilerse ya da OS periyodik turunda) zaten normale döner
                // — sadece "Gönderildi" görünümü 4sn'den biraz uzun sürebilir.
                alarmManager.set(AlarmManager.ELAPSED_REALTIME_WAKEUP, triggerAt, pending)
            }
        }
    }

    /// DatagramSocket.send() network I/O yapıyor — BroadcastReceiver.onReceive
    /// ana thread'de çalıştığı için burada DOĞRUDAN çağrılırsa Android
    /// NetworkOnMainThreadException fırlatır (önceki sürümde bu istisna
    /// sessizce yutuluyordu ve paket ASLA gitmediği halde widget "Gönderildi
    /// ✓" gösteriyordu). goAsync() ile alıcının ömrünü uzatıp gerçek işi bir
    /// arka plan thread'inde yapıyoruz; sistem, pendingResult.finish()
    /// çağrılana kadar alıcıyı canlı tutuyor.
    override fun onReceive(context: Context, intent: Intent) {
        val widgetId = intent.getIntExtra(EXTRA_WIDGET_ID, AppWidgetManager.INVALID_APPWIDGET_ID)
        if (widgetId == AppWidgetManager.INVALID_APPWIDGET_ID) return

        val action = intent.action
        val pendingResult = goAsync()
        Thread {
            try {
                when (action) {
                    ACTION_WAKE_ONE -> handleWakeOne(context, intent, widgetId)
                    ACTION_WAKE_ALL -> handleWakeAll(context, widgetId)
                }
            } finally {
                pendingResult.finish()
            }
        }.start()
    }

    private fun handleWakeOne(context: Context, intent: Intent, widgetId: Int) {
        val mac = intent.getStringExtra(EXTRA_MAC) ?: return
        val broadcastIp = intent.getStringExtra(EXTRA_BROADCAST_IP) ?: "255.255.255.255"
        val prefs = HomeWidgetPlugin.getData(context)
        val cooldownUntil = prefs.getLong(WolWidgetProvider.cooldownKey(widgetId, mac), 0L)
        // Asıl güvence burada — render'ın butonu gizlemesi sadece
        // görsel, eski bir çizimde tıklama yine de gelebilir.
        if (System.currentTimeMillis() < cooldownUntil) return

        val sent = try {
            sendMagicPacket(mac, broadcastIp)
            true
        } catch (e: Exception) {
            Log.w("MTools", "WOL widget: paket gönderilemedi: $e")
            false
        }
        if (sent) markSent(context, widgetId, mac) else markFailed(context, widgetId, mac)
        renderNow(context, widgetId)
    }

    private fun handleWakeAll(context: Context, widgetId: Int) {
        val prefs = HomeWidgetPlugin.getData(context)
        val raw = prefs.getString("wol_devices_json", null)
        val selectionRaw = prefs.getString(WolWidgetProvider.selectionKey(widgetId), null)
        val devices = try {
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
        val now = System.currentTimeMillis()
        for (i in 0 until devices.length()) {
            val d = devices.getJSONObject(i)
            val name = d.optString("name", "")
            if (selected != null && !selected.contains(name)) continue
            val mac = d.optString("mac", "")
            if (mac.isEmpty()) continue
            // WAKE_ONE'daki aynı asıl güvence — "Hepsini Uyandır"
            // butonunun kendisi tek bir cihaza bağlı olmadığı için
            // (satır-bazlı butonlar gibi) görsel olarak
            // devre-dışı-gösterilemiyor, bu yüzden art arda basılırsa
            // her cihaz için ayrı ayrı cooldown burada kontrol
            // ediliyor — aksi halde çift tıklama tüm listeye tekrar
            // paket gönderirdi.
            val cooldownUntil = prefs.getLong(WolWidgetProvider.cooldownKey(widgetId, mac), 0L)
            if (now < cooldownUntil) continue
            val sent = try {
                sendMagicPacket(mac, d.optString("broadcastIp", "255.255.255.255"))
                true
            } catch (e: Exception) {
                Log.w("MTools", "WOL widget (hepsi): $name gönderilemedi: $e")
                false
            }
            if (sent) markSent(context, widgetId, mac) else markFailed(context, widgetId, mac)
        }
        renderNow(context, widgetId)
    }

    private fun renderNow(context: Context, widgetId: Int) {
        val appWidgetManager = AppWidgetManager.getInstance(context)
        WolWidgetProvider.render(context, appWidgetManager, widgetId)
    }
}
