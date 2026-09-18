package com.velixeo.velixeo

import android.app.NotificationChannel
import android.app.NotificationManager
import android.os.Build
import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity

class MainActivity : FlutterActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val manager = getSystemService(NotificationManager::class.java)

            fun channel(
                id: String,
                name: String,
                description: String,
                importance: Int,
                vibration: Boolean = true,
            ) = NotificationChannel(id, name, importance).apply {
                this.description = description
                enableVibration(vibration)
                setShowBadge(true)
            }

            manager.createNotificationChannels(
                listOf(
                    channel(
                        "velixeo_orders",
                        "Orders & Delivery",
                        "Order progress, refill and drip-feed updates",
                        NotificationManager.IMPORTANCE_HIGH,
                    ),
                    channel(
                        "velixeo_wallet",
                        "Wallet & Payments",
                        "Wallet balance, payment and refund updates",
                        NotificationManager.IMPORTANCE_HIGH,
                    ),
                    channel(
                        "velixeo_support",
                        "Support",
                        "Support replies and ticket updates",
                        NotificationManager.IMPORTANCE_HIGH,
                    ),
                    channel(
                        "velixeo_promotions",
                        "Offers & Promotions",
                        "VELIXEO offers, campaigns and promotional updates",
                        NotificationManager.IMPORTANCE_DEFAULT,
                        vibration = false,
                    ),
                    channel(
                        "velixeo_system",
                        "System & Account",
                        "Account, security and general VELIXEO updates",
                        NotificationManager.IMPORTANCE_DEFAULT,
                    ),
                    // Keep the original channel for notifications from older app builds.
                    channel(
                        "velixeo_alerts",
                        "VELIXEO Alerts",
                        "Legacy VELIXEO notification channel",
                        NotificationManager.IMPORTANCE_HIGH,
                    ),
                ),
            )
        }
    }
}
