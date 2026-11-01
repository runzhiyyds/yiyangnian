package com.yiyangnian.yiyangnian

import android.Manifest
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.provider.Settings
import androidx.core.content.ContextCompat
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.lang.ref.WeakReference

class MainActivity : FlutterActivity() {

    companion object {
        private const val CHANNEL = "app.update/channel"
        private const val NOTIFICATION_PERMISSION_REQUEST = 4101
        const val ACTION_INSTALL_UPDATE = "com.yiyangnian.yiyangnian.INSTALL_UPDATE"
        const val EXTRA_APK_PATH = "apk_path"

        private var foregroundActivity: WeakReference<MainActivity>? = null

        fun installIfForeground(filePath: String): Boolean {
            val activity = foregroundActivity?.get() ?: return false
            activity.runOnUiThread { activity.requestInstall(filePath) }
            return true
        }
    }

    private data class PendingDownload(
        val url: String,
        val version: String,
        val fallbackUrl: String?,
        val result: MethodChannel.Result
    )

    private var pendingDownload: PendingDownload? = null
    private var pendingInstallPath: String? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        handleInstallIntent(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        handleInstallIntent(intent)
    }

    override fun onResume() {
        super.onResume()
        foregroundActivity = WeakReference(this)
        val path = pendingInstallPath
        if (
            path != null &&
            (Build.VERSION.SDK_INT < Build.VERSION_CODES.O ||
                packageManager.canRequestPackageInstalls())
        ) {
            pendingInstallPath = null
            openInstaller(path)
        }
    }

    override fun onPause() {
        if (foregroundActivity?.get() === this) foregroundActivity = null
        super.onPause()
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            CHANNEL
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "startBackgroundDownload" -> {
                    val url = call.argument<String>("url")
                    val version = call.argument<String>("version")
                    val fallbackUrl = call.argument<String>("fallbackUrl")
                    if (url.isNullOrBlank() || version.isNullOrBlank()) {
                        result.error("INVALID_ARGUMENT", "url or version is empty", null)
                        return@setMethodCallHandler
                    }
                    startDownloadWithPermission(url, version, fallbackUrl, result)
                }

                "isBackgroundDownloadActive" -> {
                    result.success(UpdateDownloadCoordinator.isActive(applicationContext))
                }

                else -> result.notImplemented()
            }
        }
    }

    private fun startDownloadWithPermission(
        url: String,
        version: String,
        fallbackUrl: String?,
        result: MethodChannel.Result
    ) {
        if (
            Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU &&
            ContextCompat.checkSelfPermission(this, Manifest.permission.POST_NOTIFICATIONS) !=
            PackageManager.PERMISSION_GRANTED
        ) {
            if (pendingDownload != null) {
                result.error("DOWNLOAD_PENDING", "another download request is pending", null)
                return
            }
            pendingDownload = PendingDownload(url, version, fallbackUrl, result)
            requestPermissions(
                arrayOf(Manifest.permission.POST_NOTIFICATIONS),
                NOTIFICATION_PERMISSION_REQUEST
            )
            return
        }
        enqueueDownload(url, version, fallbackUrl, result)
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode != NOTIFICATION_PERMISSION_REQUEST) return
        val pending = pendingDownload ?: return
        pendingDownload = null
        if (grantResults.firstOrNull() == PackageManager.PERMISSION_GRANTED) {
            enqueueDownload(
                pending.url,
                pending.version,
                pending.fallbackUrl,
                pending.result
            )
        } else {
            pending.result.error(
                "NOTIFICATION_PERMISSION_DENIED",
                "notification permission is required for background progress",
                null
            )
        }
    }

    private fun enqueueDownload(
        url: String,
        version: String,
        fallbackUrl: String?,
        result: MethodChannel.Result
    ) {
        try {
            val id = UpdateDownloadCoordinator.enqueue(
                applicationContext,
                url,
                version,
                fallbackUrl
            )
            result.success(id)
        } catch (error: Exception) {
            result.error("DOWNLOAD_START_FAILED", error.message, null)
        }
    }

    private fun handleInstallIntent(intent: Intent?) {
        if (intent?.action != ACTION_INSTALL_UPDATE) return
        val path = intent.getStringExtra(EXTRA_APK_PATH) ?: return
        requestInstall(path)
    }

    internal fun requestInstall(filePath: String) {
        val apkFile = File(filePath)
        if (!apkFile.exists()) {
            throw IllegalArgumentException("APK file not found: $filePath")
        }
        if (
            Build.VERSION.SDK_INT >= Build.VERSION_CODES.O &&
            !packageManager.canRequestPackageInstalls()
        ) {
            pendingInstallPath = filePath
            startActivity(
                Intent(
                    Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,
                    Uri.parse("package:$packageName")
                )
            )
            return
        }
        openInstaller(filePath)
    }

    private fun openInstaller(filePath: String) {
        val apkFile = File(filePath)
        if (!apkFile.exists()) return
        val uri = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
            FileProvider.getUriForFile(
                this,
                "$packageName.fileprovider",
                apkFile
            )
        } else {
            Uri.fromFile(apkFile)
        }
        startActivity(
            Intent(Intent.ACTION_VIEW).apply {
                setDataAndType(uri, "application/vnd.android.package-archive")
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            }
        )
    }
}
