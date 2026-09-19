package com.velixeo.velixeo

import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.provider.Settings
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.net.HttpURLConnection
import java.net.URL

class MainActivity : FlutterActivity() {
    companion object {
        private const val UPDATE_CHANNEL = "com.velixeo.velixeo/updater"
    }

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

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, UPDATE_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "getAppVersion" -> {
                        val info = packageManager.getPackageInfo(packageName, 0)
                        result.success(info.versionName ?: "0.0.0")
                    }

                    "canInstallPackages" -> {
                        val allowed = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                            packageManager.canRequestPackageInstalls()
                        } else {
                            true
                        }
                        result.success(allowed)
                    }

                    "openInstallPermission" -> {
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                            startActivity(
                                Intent(
                                    Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,
                                    Uri.parse("package:$packageName"),
                                ),
                            )
                        }
                        result.success(null)
                    }

                    "downloadAndInstallApk" -> {
                        val url = call.argument<String>("url")
                        val version = call.argument<String>("version") ?: "latest"
                        if (url.isNullOrBlank()) {
                            result.error("invalid_url", "Update URL is missing.", null)
                            return@setMethodCallHandler
                        }
                        downloadAndInstall(url, version, result)
                    }

                    else -> result.notImplemented()
                }
            }
    }

    private fun downloadAndInstall(
        sourceUrl: String,
        version: String,
        result: MethodChannel.Result,
    ) {
        Thread {
            try {
                val updateDir = File(cacheDir, "updates").apply { mkdirs() }
                updateDir.listFiles()?.forEach { it.delete() }
                val apk = File(updateDir, "VELIXEO-$version.apk")

                var currentUrl = URL(sourceUrl)
                var connection: HttpURLConnection
                var redirects = 0
                while (true) {
                    connection = (currentUrl.openConnection() as HttpURLConnection).apply {
                        connectTimeout = 15_000
                        readTimeout = 60_000
                        instanceFollowRedirects = false
                        requestMethod = "GET"
                        setRequestProperty("User-Agent", "VELIXEO-Android-Updater")
                        connect()
                    }
                    val status = connection.responseCode
                    if (status in 300..399 && redirects < 6) {
                        val location = connection.getHeaderField("Location")
                            ?: throw IllegalStateException("Update redirect is missing a location.")
                        connection.disconnect()
                        currentUrl = URL(currentUrl, location)
                        redirects += 1
                        continue
                    }
                    if (status !in 200..299) {
                        throw IllegalStateException("Update download failed with HTTP $status.")
                    }
                    break
                }

                connection.inputStream.use { input ->
                    apk.outputStream().use { output -> input.copyTo(output) }
                }
                connection.disconnect()

                if (!apk.exists() || apk.length() < 1_000_000) {
                    throw IllegalStateException("Downloaded APK is invalid.")
                }

                runOnUiThread {
                    try {
                        val uri = FileProvider.getUriForFile(
                            this,
                            "$packageName.fileprovider",
                            apk,
                        )
                        val intent = Intent(Intent.ACTION_VIEW).apply {
                            setDataAndType(uri, "application/vnd.android.package-archive")
                            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                        }
                        startActivity(intent)
                        result.success(null)
                    } catch (error: Exception) {
                        result.error("install_failed", error.message, null)
                    }
                }
            } catch (error: Exception) {
                runOnUiThread {
                    result.error("download_failed", error.message, null)
                }
            }
        }.start()
    }
}
