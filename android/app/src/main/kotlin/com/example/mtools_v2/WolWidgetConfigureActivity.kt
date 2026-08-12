package com.example.mtools_v2

import android.app.Activity
import android.appwidget.AppWidgetManager
import android.content.Intent
import android.content.SharedPreferences
import android.os.Bundle
import android.view.Gravity
import android.widget.Button
import android.widget.CheckBox
import android.widget.LinearLayout
import android.widget.ScrollView
import android.widget.TextView
import es.antonborri.home_widget.HomeWidgetPlugin
import org.json.JSONArray

/// WOL widget'ı ana ekrana eklenirken (veya uzun basılıp "Yapılandır"
/// denince) açılır — kullanıcı bu widget ÖRNEĞİNDE hangi kayıtlı WOL
/// cihazlarının görüneceğini seçer.
///
/// `ProxmoxWidgetConfigureActivity` ile BİREBİR AYNI şablon — appWidgetId
/// bazlı seçim, "veri yok" fallback'i, varsayılan hepsi işaretli. Aynı
/// gerekçeler (native Activity, Flutter engine açmadan) burada da geçerli.
class WolWidgetConfigureActivity : Activity() {
    private var appWidgetId = AppWidgetManager.INVALID_APPWIDGET_ID
    private val checkBoxes = mutableListOf<CheckBox>()
    private lateinit var statusText: TextView

    companion object {
        private const val COLOR_BG = 0xFF1A1A1A.toInt()
        private const val COLOR_TEXT_PRIMARY = 0xFFE2E8F0.toInt()
        private const val COLOR_TEXT_MUTED = 0xFF6B7280.toInt()
        private const val COLOR_ACCENT = 0xFF4A9EFF.toInt()
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setResult(Activity.RESULT_CANCELED)

        appWidgetId = intent?.extras?.getInt(
            AppWidgetManager.EXTRA_APPWIDGET_ID,
            AppWidgetManager.INVALID_APPWIDGET_ID,
        ) ?: AppWidgetManager.INVALID_APPWIDGET_ID

        if (appWidgetId == AppWidgetManager.INVALID_APPWIDGET_ID) {
            finish()
            return
        }

        setContentView(buildLayout())
    }

    private fun buildLayout(): ScrollView {
        val prefs = HomeWidgetPlugin.getData(this)
        val deviceNames = readAvailableDeviceNames(prefs)

        val root = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setBackgroundColor(COLOR_BG)
            val pad = dp(20)
            setPadding(pad, dp(32), pad, pad)
        }

        root.addView(TextView(this).apply {
            text = "Gösterilecek cihazlar"
            setTextColor(COLOR_TEXT_PRIMARY)
            textSize = 18f
        })

        if (deviceNames.isEmpty()) {
            root.addView(TextView(this).apply {
                text = "Henüz kayıtlı cihaz yok — önce uygulamayı açıp Wake on " +
                    "LAN ekranından cihaz ekleyin. Şimdilik tüm cihazlar " +
                    "gösterilecek, widget'a daha sonra uzun basıp " +
                    "\"Yapılandır\" ile seçim yapabilirsiniz."
                setTextColor(COLOR_TEXT_MUTED)
                textSize = 13f
                setPadding(0, dp(12), 0, dp(24))
            })
            root.addView(Button(this).apply {
                text = "Tamam"
                setOnClickListener { finishConfiguring(emptyList()) }
            })
            statusText = TextView(this)
            return ScrollView(this).apply { addView(root) }
        }

        root.addView(TextView(this).apply {
            text = "Bu widget'ta hangi cihazların görüneceğini seçin. Aynı " +
                "widget'ı birden fazla eklerseniz her biri kendi seçimini " +
                "korur."
            setTextColor(COLOR_TEXT_MUTED)
            textSize = 13f
            setPadding(0, dp(8), 0, dp(20))
        })

        val existing = readSelection(prefs, appWidgetId)
        for (name in deviceNames) {
            val cb = CheckBox(this).apply {
                text = name
                setTextColor(COLOR_TEXT_PRIMARY)
                isChecked = existing?.contains(name) ?: true
                setPadding(0, dp(6), 0, dp(6))
            }
            checkBoxes.add(cb)
            root.addView(cb)
        }

        statusText = TextView(this).apply {
            setTextColor(0xFFD95C5C.toInt())
            textSize = 12f
            setPadding(0, dp(8), 0, 0)
        }
        root.addView(statusText)

        root.addView(Button(this).apply {
            text = "Kaydet"
            setTextColor(COLOR_ACCENT)
            gravity = Gravity.CENTER
            setPadding(0, dp(16), 0, 0)
            setOnClickListener {
                val selected = checkBoxes.filter { it.isChecked }.map { it.text.toString() }
                if (selected.isEmpty()) {
                    statusText.text = "En az bir cihaz seçmelisiniz."
                } else {
                    finishConfiguring(selected)
                }
            }
        })

        return ScrollView(this).apply { addView(root) }
    }

    private fun readAvailableDeviceNames(prefs: SharedPreferences): List<String> {
        val raw = prefs.getString("wol_devices_json", null) ?: return emptyList()
        return try {
            val arr = JSONArray(raw)
            (0 until arr.length()).mapNotNull { i ->
                val name = arr.getJSONObject(i).optString("name", "")
                name.ifEmpty { null }
            }
        } catch (_: Exception) {
            emptyList()
        }
    }

    private fun readSelection(prefs: SharedPreferences, id: Int): Set<String>? {
        val raw = prefs.getString(WolWidgetProvider.selectionKey(id), null) ?: return null
        return try {
            val arr = JSONArray(raw)
            (0 until arr.length()).map { arr.getString(it) }.toSet()
        } catch (_: Exception) {
            null
        }
    }

    private fun finishConfiguring(selected: List<String>) {
        val prefs = HomeWidgetPlugin.getData(this)
        if (selected.isNotEmpty()) {
            prefs.edit()
                .putString(WolWidgetProvider.selectionKey(appWidgetId), JSONArray(selected).toString())
                .apply()
        }

        val appWidgetManager = AppWidgetManager.getInstance(this)
        WolWidgetProvider.render(this, appWidgetManager, appWidgetId)

        val resultValue = Intent().putExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, appWidgetId)
        setResult(Activity.RESULT_OK, resultValue)
        finish()
    }

    private fun dp(value: Int): Int = (value * resources.displayMetrics.density).toInt()
}
