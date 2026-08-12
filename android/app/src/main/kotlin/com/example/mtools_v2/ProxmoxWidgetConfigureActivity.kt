package com.example.mtools_v2

import android.app.Activity
import android.appwidget.AppWidgetManager
import android.content.Intent
import android.content.SharedPreferences
import android.content.res.ColorStateList
import android.os.Build
import android.os.Bundle
import android.view.Gravity
import android.widget.Button
import android.widget.CheckBox
import android.widget.LinearLayout
import android.widget.ScrollView
import android.widget.TextView
import androidx.core.content.ContextCompat
import es.antonborri.home_widget.HomeWidgetPlugin
import org.json.JSONArray
import org.json.JSONObject

/// "Sistem" (Proxmox) widget'ı ana ekrana eklenirken — ya da uzun basılıp
/// "Yapılandır" denince, Android bunu `android:configure` sayesinde otomatik
/// sağlıyor — açılan ekran. Kullanıcı bu widget ÖRNEĞİNDE hangi Proxmox
/// node'larının görüneceğini seçer.
///
/// Bilinçli olarak Flutter değil, sade bir native Activity — Flutter
/// engine'i başlatmak bir checkbox listesi için gereksiz ağır olurdu.
/// Checkbox listesi, widget'ın zaten okuduğu "proxmox_nodes_json"tan
/// üretiliyor — ayrı bir veri kaynağı yok.
///
/// appWidgetId bazlı: her widget örneği "proxmox_widget_nodes_$id"
/// anahtarında kendi seçimini tutar (bkz. ProxmoxWidgetProvider.selectionKey).
/// Widget silinince ProxmoxWidgetProvider.onDeleted bu anahtarı temizler;
/// aynı widget tekrar eklenince Android YENİ bir appWidgetId atadığı için
/// (eskisini asla yeniden kullanmaz) yeni örnek zaten temiz başlar — bu
/// ekran o yeni id için hiç kayıt bulamaz, tüm node'lar varsayılan olarak
/// işaretli açılır.
class ProxmoxWidgetConfigureActivity : Activity() {
    private var appWidgetId = AppWidgetManager.INVALID_APPWIDGET_ID
    private val checkBoxes = mutableListOf<CheckBox>()
    private lateinit var statusText: TextView

    // Sabit hex yerine widget'ların kendisiyle (ProxmoxWidgetProvider vb.)
    // AYNI colors.xml token'ları — iki yerde ayrı ayrı tutulan ama sayısal
    // olarak hep eşleşmesi gereken bir çift artık tek kaynaktan geliyor.
    private val colorBg by lazy { ContextCompat.getColor(this, R.color.widget_bg) }
    private val colorTextPrimary by lazy { ContextCompat.getColor(this, R.color.widget_text_primary) }
    private val colorTextMuted by lazy { ContextCompat.getColor(this, R.color.widget_text_muted) }
    private val colorAccent by lazy { ContextCompat.getColor(this, R.color.widget_primary) }
    private val colorError by lazy { ContextCompat.getColor(this, R.color.widget_error) }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        // Kullanıcı geri tuşuyla/dışına dokunarak çıkarsa Android widget
        // yerleştirmesini iptal eder — bu standart ve beklenen davranış,
        // "Kaydet" dışında bir yol RESULT_OK üretmemeli.
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
        val nodeNames = readAvailableNodeNames(prefs)

        val root = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setBackgroundColor(colorBg)
            val pad = dp(20)
            setPadding(pad, dp(32), pad, pad)
        }

        root.addView(TextView(this).apply {
            text = "Gösterilecek sunucular"
            setTextColor(colorTextPrimary)
            textSize = 18f
        })

        if (nodeNames.isEmpty()) {
            root.addView(TextView(this).apply {
                text = "Henüz sunucu verisi yok — önce uygulamayı açıp Proxmox " +
                    "sunucunuzu ekleyin. Şimdilik tüm sunucular gösterilecek, " +
                    "widget'a daha sonra uzun basıp \"Yapılandır\" ile seçim " +
                    "yapabilirsiniz."
                setTextColor(colorTextMuted)
                textSize = 13f
                setPadding(0, dp(12), 0, dp(24))
            })
            root.addView(saveButton(text = "Tamam") { finishConfiguring(emptyList()) })
            statusText = TextView(this)
            return ScrollView(this).apply {
                setBackgroundColor(colorBg)
                addView(root)
            }
        }

        root.addView(TextView(this).apply {
            text = "Bu widget'ta hangi sunucuların görüneceğini seçin. Aynı " +
                "widget'ı birden fazla eklerseniz her biri kendi seçimini " +
                "korur."
            setTextColor(colorTextMuted)
            textSize = 13f
            setPadding(0, dp(8), 0, dp(20))
        })

        val existing = readSelection(prefs, appWidgetId)
        for (name in nodeNames) {
            val cb = CheckBox(this).apply {
                text = name
                setTextColor(colorTextPrimary)
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                    buttonTintList = ColorStateList.valueOf(colorAccent)
                }
                // Seçim daha önce hiç kaydedilmemişse (ilk kurulum ya da
                // widget silinip yeniden eklendiği için yeni bir appWidgetId
                // atanmışsa) varsayılan hepsi işaretli — kullanıcı hiç
                // dokunmadan Kaydet'e basarsa mevcut "hepsini göster"
                // davranışı korunur.
                isChecked = existing?.contains(name) ?: true
            }
            checkBoxes.add(cb)
            // Widget'ların kendi node/UPS/cihaz satırlarıyla aynı "kart"
            // dili (widget_row_background: yuvarlatılmış, widget_bg_light
            // zeminli yüzey) — çıplak bir checkbox listesi yerine.
            root.addView(LinearLayout(this).apply {
                setBackgroundResource(R.drawable.widget_row_background)
                val padH = dp(12)
                setPadding(padH, dp(4), padH, dp(4))
                layoutParams = LinearLayout.LayoutParams(
                    LinearLayout.LayoutParams.MATCH_PARENT,
                    LinearLayout.LayoutParams.WRAP_CONTENT,
                ).apply { bottomMargin = dp(8) }
                addView(cb)
            })
        }

        statusText = TextView(this).apply {
            setTextColor(colorError)
            textSize = 12f
            setPadding(0, dp(8), 0, 0)
        }
        root.addView(statusText)

        root.addView(saveButton(text = "Kaydet") {
            val selected = checkBoxes.filter { it.isChecked }.map { it.text.toString() }
            if (selected.isEmpty()) {
                statusText.text = "En az bir sunucu seçmelisiniz."
            } else {
                finishConfiguring(selected)
            }
        })

        return ScrollView(this).apply {
            setBackgroundColor(colorBg)
            addView(root)
        }
    }

    /// widget_configure_button_bg zeminli, widget_primary metinli tek tip
    /// aksiyon butonu — "Tamam" (veri yok) ve "Kaydet" akışlarının ikisinde
    /// de kullanılıyor, widget'ların kendi buton diliyle (widget_wol_button_bg)
    /// aynı desende.
    private fun saveButton(text: String, onClick: () -> Unit): Button = Button(this).apply {
        this.text = text
        setTextColor(colorAccent)
        gravity = Gravity.CENTER
        setBackgroundResource(R.drawable.widget_configure_button_bg)
        minimumHeight = dp(48)
        val layoutParams = LinearLayout.LayoutParams(
            LinearLayout.LayoutParams.MATCH_PARENT,
            LinearLayout.LayoutParams.WRAP_CONTENT,
        ).apply { topMargin = dp(16) }
        this.layoutParams = layoutParams
        setOnClickListener { onClick() }
    }

    private fun readAvailableNodeNames(prefs: SharedPreferences): List<String> {
        val raw = prefs.getString("proxmox_nodes_json", null) ?: return emptyList()
        return try {
            // ProxmoxWidgetProvider'la aynı şema: {"configured": bool,
            // "nodes": [...]} — çıplak dizi değil.
            val arr = JSONObject(raw).optJSONArray("nodes") ?: JSONArray()
            (0 until arr.length()).mapNotNull { i ->
                val name = arr.getJSONObject(i).optString("name", "")
                name.ifEmpty { null }
            }
        } catch (_: Exception) {
            emptyList()
        }
    }

    private fun readSelection(prefs: SharedPreferences, id: Int): Set<String>? {
        val raw = prefs.getString(ProxmoxWidgetProvider.selectionKey(id), null) ?: return null
        return try {
            val arr = JSONArray(raw)
            (0 until arr.length()).map { arr.getString(it) }.toSet()
        } catch (_: Exception) {
            null
        }
    }

    /// [selected] boşsa (veri yokken "Tamam" denmişse) hiçbir şey yazılmaz —
    /// anahtar hiç oluşmaz, ProxmoxWidgetProvider'ın "seçim yok → hepsini
    /// göster" geriye-dönük-uyumlu yolu devreye girer.
    private fun finishConfiguring(selected: List<String>) {
        val prefs = HomeWidgetPlugin.getData(this)
        if (selected.isNotEmpty()) {
            prefs.edit()
                .putString(ProxmoxWidgetProvider.selectionKey(appWidgetId), JSONArray(selected).toString())
                .apply()
        }

        val appWidgetManager = AppWidgetManager.getInstance(this)
        ProxmoxWidgetProvider.render(this, appWidgetManager, appWidgetId)

        val resultValue = Intent().putExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, appWidgetId)
        setResult(Activity.RESULT_OK, resultValue)
        finish()
    }

    private fun dp(value: Int): Int = (value * resources.displayMetrics.density).toInt()
}
