package com.yiyangnian.yiyangnian

import android.app.DownloadManager
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Environment
import androidx.core.app.NotificationCompat
import java.io.File

internal object UpdateDownloadCoordinator {
    private const val PREFS = "app_update_download"
    private const val KEY_DOWNLOAD_ID = "download_id"
    private const val KEY_FILE_PATH = "file_path"
    private const val KEY_FALLBACK_URL = "fallback_url"
    private const val NOTIFICATION_CHANNEL = "app_update"
    private const val NOTIFICATION_ID = 4102

    fun enqueue(
        context: Context,
        url: String,
        version: String,
        fallbackUrl: String?
    ): Long {
        val safeVersion = version.replace(Regex("[^0-9A-Za-z._-]"), "-")
        val fileName = "yiyangnian-$safeVersion.apk"
        val directory = context.getExternalFilesDir(Environment.DIRECTORY_DOWNLOADS)
            ?: throw IllegalStateException("无法访问应用下载目录")
        val targetFile = File(directory, fileName)
        if (targetFile.exists()) targetFile.delete()

        val request = DownloadManager.Request(Uri.parse(url)).apply {
            setTitle("正在下载颐养年 v$version")
            setDescription("下载完成后可直接安装")
            setMimeType("application/vnd.android.package-archive")
            setNotificationVisibility(
                DownloadManager.Request.VISIBILITY_VISIBLE_NOTIFY_COMPLETED
            )
            setAllowedOverMetered(true)
            setAllowedOverRoaming(false)
            addRequestHeader("User-Agent", "Yiyangnian-Android-Updater")
            setDestinationInExternalFilesDir(
                context,
                Environment.DIRECTORY_DOWNLOADS,
                fileName
            )
        }
        val manager = context.getSystemService(Context.DOWNLOAD_SERVICE) as DownloadManager
        val downloadId = manager.enqueue(request)
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .edit()
            .putLong(KEY_DOWNLOAD_ID, downloadId)
            .putString(KEY_FILE_PATH, targetFile.absolutePath)
            .putString(KEY_FALLBACK_URL, fallbackUrl)
            .apply()
        return downloadId
    }

    fun isActive(context: Context): Boolean {
        val id = preferences(context).getLong(KEY_DOWNLOAD_ID, -1L)
        if (id < 0) return false
        val manager = context.getSystemService(Context.DOWNLOAD_SERVICE) as DownloadManager
        return try {
            manager.query(DownloadManager.Query().setFilterById(id)).use { cursor ->
                if (!cursor.moveToFirst()) return@use false
                val status = cursor.getInt(
                    cursor.getColumnIndexOrThrow(DownloadManager.COLUMN_STATUS)
                )
                status == DownloadManager.STATUS_PENDING ||
                    status == DownloadManager.STATUS_RUNNING ||
                    status == DownloadManager.STATUS_PAUSED
            }
        } catch (_: Exception) {
            false
        }
    }

    fun handleCompletion(context: Context, completedId: Long) {
        val prefs = preferences(context)
        val expectedId = prefs.getLong(KEY_DOWNLOAD_ID, -1L)
        if (completedId != expectedId) return
        val filePath = prefs.getString(KEY_FILE_PATH, null)
        val fallbackUrl = prefs.getString(KEY_FALLBACK_URL, null)
        val manager = context.getSystemService(Context.DOWNLOAD_SERVICE) as DownloadManager
        var successful = false
        try {
            manager.query(DownloadManager.Query().setFilterById(completedId)).use { cursor ->
                if (cursor.moveToFirst()) {
                    successful = cursor.getInt(
                        cursor.getColumnIndexOrThrow(DownloadManager.COLUMN_STATUS)
                    ) == DownloadManager.STATUS_SUCCESSFUL
                }
            }
        } catch (_: Exception) {
            successful = false
        }
        prefs.edit().remove(KEY_DOWNLOAD_ID).apply()

        if (successful && filePath != null && File(filePath).exists()) {
            if (!MainActivity.installIfForeground(filePath)) {
                showInstallNotification(context, filePath)
            }
        } else {
            showFailureNotification(context, fallbackUrl)
        }
    }

    private fun preferences(context: Context) =
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)

    private fun notificationManager(context: Context): NotificationManager {
        val manager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            manager.createNotificationChannel(
                NotificationChannel(
                    NOTIFICATION_CHANNEL,
                    "应用更新",
                    NotificationManager.IMPORTANCE_HIGH
                ).apply {
                    description = "新版本下载与安装提醒"
                }
            )
        }
        return manager
    }

    private fun showInstallNotification(context: Context, filePath: String) {
        val intent = Intent(context, MainActivity::class.java).apply {
            action = MainActivity.ACTION_INSTALL_UPDATE
            putExtra(MainActivity.EXTRA_APK_PATH, filePath)
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP)
        }
        val pendingIntent = PendingIntent.getActivity(
            context,
            4102,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        val notification = NotificationCompat.Builder(context, NOTIFICATION_CHANNEL)
            .setSmallIcon(android.R.drawable.stat_sys_download_done)
            .setContentTitle("更新下载完成")
            .setContentText("点击进入安装页面")
            .setContentIntent(pendingIntent)
            .setAutoCancel(true)
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .build()
        notificationManager(context).notify(NOTIFICATION_ID, notification)
    }

    private fun showFailureNotification(context: Context, fallbackUrl: String?) {
        if (fallbackUrl.isNullOrBlank()) return
        val intent = Intent(Intent.ACTION_VIEW, Uri.parse(fallbackUrl)).apply {
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        }
        val pendingIntent = PendingIntent.getActivity(
            context,
            4103,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        val notification = NotificationCompat.Builder(context, NOTIFICATION_CHANNEL)
            .setSmallIcon(android.R.drawable.stat_notify_error)
            .setContentTitle("应用内下载失败")
            .setContentText("点击前往蒲公英下载")
            .setContentIntent(pendingIntent)
            .setAutoCancel(true)
            .build()
        notificationManager(context).notify(NOTIFICATION_ID, notification)
    }
}

class UpdateDownloadReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != DownloadManager.ACTION_DOWNLOAD_COMPLETE) return
        val downloadId = intent.getLongExtra(DownloadManager.EXTRA_DOWNLOAD_ID, -1L)
        if (downloadId >= 0) {
            UpdateDownloadCoordinator.handleCompletion(context.applicationContext, downloadId)
        }
    }
}
