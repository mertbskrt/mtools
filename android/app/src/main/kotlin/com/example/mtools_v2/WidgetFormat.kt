package com.example.mtools_v2

import java.util.Locale

/// Widget'larda büyük sayıları kısaltmak için (12400 -> "12.4K").
object WidgetFormat {
    fun compactCount(value: Int): String {
        return when {
            value >= 1_000_000 -> String.format(Locale.US, "%.1fM", value / 1_000_000.0)
            value >= 1_000 -> String.format(Locale.US, "%.1fK", value / 1_000.0)
            else -> value.toString()
        }
    }

    fun uptime(seconds: Int): String {
        if (seconds <= 0) return "-"
        val days = seconds / 86400
        val hours = (seconds % 86400) / 3600
        return if (days > 0) "${days}g ${hours}s çalışıyor" else "${hours}s çalışıyor"
    }

    /// Widget'ın gerçekten yenilendiğini gösteren "az önce / X dk önce" metni
    /// — hem otomatik hem elle yenilemenin görünür bir kanıtı.
    fun relativeUpdatedAt(epochMillis: Long): String {
        if (epochMillis <= 0) return ""
        val diffSeconds = (System.currentTimeMillis() - epochMillis) / 1000
        return when {
            diffSeconds < 10 -> "az önce"
            diffSeconds < 60 -> "${diffSeconds}sn önce"
            diffSeconds < 3600 -> "${diffSeconds / 60}dk önce"
            else -> "${diffSeconds / 3600}sa önce"
        }
    }
}
