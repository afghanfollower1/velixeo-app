package com.velixeo.velixeo

import android.app.DownloadManager
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.Environment
import android.provider.Settings
import androidx.core.app.NotificationCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    companion object {
        private const val UPDATE_CHANNEL = "com.velixeo.velixeo/updater"
        private const val UPDATE_PREFS = "velixeo_update"
        private const val PREF_DOWNLOAD_ID = "download_id"
        private const val PREF_VERSION = "version"
        private const val APK_MIME = "application/vnd.android.package-archive"
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
                        "velixeo_updates",
                        "App updates",
                        "VELIXEO app download and installation updates",
                        NotificationManager.IMPORTANCE_DEFAULT,
                        vibration = false,
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
                        val current = info.versionName ?: "0.0.0"
                        val prefs = getSharedPreferences(UPDATE_PREFS, Context.MODE_PRIVATE)
                        if (prefs.getString(PREF_VERSION, null) == current) {
                            prefs.edit().remove(PREF_DOWNLOAD_ID).remove(PREF_VERSION).apply()
                        }
                        result.success(current)
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

                    "startUpdateDownload", "downloadAndInstallApk" -> {
                        val url = call.argument<String>("url")
                        val version = call.argument<String>("version") ?: "latest"
                        if (url.isNullOrBlank()) {
                            result.error("invalid_url", "Update URL is missing.", null)
                            return@setMethodCallHandler
                        }
                        try {
                            result.success(startUpdateDownload(url, version))
                        } catch (error: Exception) {
                            result.error("download_start_failed", error.message, null)
                        }
                    }

                    "getUpdateDownloadStatus" -> {
                        val requested = call.argument<Number>("downloadId")?.toLong()
                        val id = requested ?: storedDownloadId()
                        if (id == null) {
                            result.success(null)
                        } else {
                            result.success(queryDownload(id))
                        }
                    }

                    "openDownloadedUpdate" -> {
                        val requested = call.argument<Number>("downloadId")?.toLong()
                        val id = requested ?: storedDownloadId()
                        if (id == null) {
                            result.error("download_missing", "No downloaded update was found.", null)
                            return@setMethodCallHandler
                        }
                        try {
                            openDownloadedUpdate(id)
                            result.success(null)
                        } catch (error: Exception) {
                            result.error("install_failed", error.message, null)
                        }
                    }

                    "cancelUpdateDownload" -> {
                        val requested = call.argument<Number>("downloadId")?.toLong()
                        val id = requested ?: storedDownloadId()
                        if (id != null) {
                            downloadManager().remove(id)
                            clearStoredDownload(id)
                        }
                        result.success(null)
                    }

                    else -> result.notImplemented()
                }
            }
    }

    private fun downloadManager(): DownloadManager =
        getSystemService(Context.DOWNLOAD_SERVICE) as DownloadManager

    private fun storedDownloadId(): Long? {
        val value = getSharedPreferences(UPDATE_PREFS, Context.MODE_PRIVATE)
            .getLong(PREF_DOWNLOAD_ID, -1L)
        return value.takeIf { it > 0L }
    }

    private fun clearStoredDownload(id: Long) {
        val prefs = getSharedPreferences(UPDATE_PREFS, Context.MODE_PRIVATE)
        if (prefs.getLong(PREF_DOWNLOAD_ID, -1L) == id) {
            prefs.edit().remove(PREF_DOWNLOAD_ID).remove(PREF_VERSION).apply()
        }
    }

    private fun startUpdateDownload(sourceUrl: String, version: String): Map<String, Any?> {
        val prefs = getSharedPreferences(UPDATE_PREFS, Context.MODE_PRIVATE)
        val existingId = prefs.getLong(PREF_DOWNLOAD_ID, -1L)
        val existingVersion = prefs.getString(PREF_VERSION, null)
        if (existingId > 0L && existingVersion == version) {
            val existing = queryDownload(existingId)
            val status = existing?.get("status") as? String
            if (existing != null && status !in setOf("failed", "missing")) {
                return existing
            }
            downloadManager().remove(existingId)
        }

        val request = DownloadManager.Request(Uri.parse(sourceUrl))
            .setTitle("VELIXEO $version")
            .setDescription("Downloading signed app update")
            .setMimeType(APK_MIME)
            .setAllowedOverMetered(true)
            .setAllowedOverRoaming(false)
            .setNotificationVisibility(DownloadManager.Request.VISIBILITY_VISIBLE_NOTIFY_COMPLETED)
            .setDestinationInExternalFilesDir(
                this,
                Environment.DIRECTORY_DOWNLOADS,
                "VELIXEO-v$version-release.apk",
            )
            .addRequestHeader("User-Agent", "VELIXEO-Android-Updater")

        val id = downloadManager().enqueue(request)
        if (id <= 0L) {
            throw IllegalStateException("Android DownloadManager could not start the update.")
        }

        prefs.edit()
            .putLong(PREF_DOWNLOAD_ID, id)
            .putString(PREF_VERSION, version)
            .apply()

        return queryDownload(id) ?: mapOf(
            "downloadId" to id,
            "version" to version,
            "status" to "pending",
            "downloadedBytes" to 0L,
            "totalBytes" to -1L,
            "progress" to -1.0,
        )
    }

    private fun queryDownload(id: Long): Map<String, Any?>? {
        val cursor = downloadManager().query(
            DownloadManager.Query().setFilterById(id),
        )
        cursor.use {
            if (!it.moveToFirst()) {
                clearStoredDownload(id)
                return mapOf(
                    "downloadId" to id,
                    "status" to "missing",
                    "downloadedBytes" to 0L,
                    "totalBytes" to -1L,
                    "progress" to -1.0,
                )
            }

            fun longColumn(name: String): Long {
                val index = it.getColumnIndex(name)
                return if (index >= 0) it.getLong(index) else -1L
            }

            val rawStatus = longColumn(DownloadManager.COLUMN_STATUS).toInt()
            val downloaded = longColumn(DownloadManager.COLUMN_BYTES_DOWNLOADED_SO_FAR)
            val total = longColumn(DownloadManager.COLUMN_TOTAL_SIZE_BYTES)
            val reason = longColumn(DownloadManager.COLUMN_REASON)
            val progress = if (total > 0L && downloaded >= 0L) {
                (downloaded.toDouble() / total.toDouble()).coerceIn(0.0, 1.0)
            } else {
                -1.0
            }
            val status = when (rawStatus) {
                DownloadManager.STATUS_PENDING -> "pending"
                DownloadManager.STATUS_RUNNING -> "running"
                DownloadManager.STATUS_PAUSED -> "paused"
                DownloadManager.STATUS_SUCCESSFUL -> "successful"
                DownloadManager.STATUS_FAILED -> "failed"
                else -> "unknown"
            }
            val prefs = getSharedPreferences(UPDATE_PREFS, Context.MODE_PRIVATE)
            return mapOf(
                "downloadId" to id,
                "version" to prefs.getString(PREF_VERSION, null),
                "status" to status,
                "downloadedBytes" to downloaded,
                "totalBytes" to total,
                "progress" to progress,
                "reason" to reason,
            )
        }
    }

    private fun openDownloadedUpdate(id: Long) {
        val state = queryDownload(id)
        if (state?.get("status") != "successful") {
            throw IllegalStateException("The update has not finished downloading yet.")
        }

        val uri = downloadManager().getUriForDownloadedFile(id)
            ?: throw IllegalStateException("The downloaded APK could not be opened.")

        val intent = Intent(Intent.ACTION_VIEW).apply {
            setDataAndType(uri, APK_MIME)
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        }
        startActivity(intent)
    }
}

class UpdateDownloadReceiver : BroadcastReceiver() {
    companion object {
        private const val UPDATE_PREFS = "velixeo_update"
        private const val PREF_DOWNLOAD_ID = "download_id"
        private const val APK_MIME = "application/vnd.android.package-archive"
        private const val UPDATE_NOTIFICATION_ID = 2085
    }

    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != DownloadManager.ACTION_DOWNLOAD_COMPLETE) return

        val completedId = intent.getLongExtra(DownloadManager.EXTRA_DOWNLOAD_ID, -1L)
        if (completedId <= 0L) return

        val prefs = context.getSharedPreferences(UPDATE_PREFS, Context.MODE_PRIVATE)
        if (prefs.getLong(PREF_DOWNLOAD_ID, -1L) != completedId) return

        val manager = context.getSystemService(Context.DOWNLOAD_SERVICE) as DownloadManager
        val cursor = manager.query(DownloadManager.Query().setFilterById(completedId))
        val successful = cursor.use {
            if (!it.moveToFirst()) {
                false
            } else {
                val index = it.getColumnIndex(DownloadManager.COLUMN_STATUS)
                index >= 0 && it.getInt(index) == DownloadManager.STATUS_SUCCESSFUL
            }
        }
        if (!successful) return

        val uri = manager.getUriForDownloadedFile(completedId) ?: return
        val installIntent = Intent(Intent.ACTION_VIEW).apply {
            setDataAndType(uri, APK_MIME)
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        }
        val pendingIntent = PendingIntent.getActivity(
            context,
            UPDATE_NOTIFICATION_ID,
            installIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val notifications = context.getSystemService(NotificationManager::class.java)
            if (notifications.getNotificationChannel("velixeo_updates") == null) {
                notifications.createNotificationChannel(
                    NotificationChannel(
                        "velixeo_updates",
                        "App updates",
                        NotificationManager.IMPORTANCE_DEFAULT,
                    ).apply {
                        description = "VELIXEO app download and installation updates"
                        enableVibration(false)
                    },
                )
            }
        }

        try {
            val notification = NotificationCompat.Builder(context, "velixeo_updates")
                .setSmallIcon(R.drawable.ic_stat_velixeo)
                .setContentTitle("VELIXEO update ready")
                .setContentText("Download complete. Tap to install the update.")
                .setPriority(NotificationCompat.PRIORITY_DEFAULT)
                .setAutoCancel(true)
                .setContentIntent(pendingIntent)
                .build()
            val notifications =
                context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            notifications.notify(UPDATE_NOTIFICATION_ID, notification)
        } catch (_: SecurityException) {
            // Android DownloadManager still keeps its own completion notification.
        }
    }
}
