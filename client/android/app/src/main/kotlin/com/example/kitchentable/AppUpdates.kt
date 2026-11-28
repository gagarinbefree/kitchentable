package com.example.kitchentable

import android.app.Activity
import android.content.ActivityNotFoundException
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.provider.Settings
import androidx.core.content.FileProvider
import androidx.core.content.pm.PackageInfoCompat
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import java.io.File
import kotlin.concurrent.thread

class UpdateFileProvider : FileProvider()

@Suppress("DEPRECATION")
internal fun registerUpdates(activity: Activity, messenger: BinaryMessenger) {
    val pm = activity.packageManager
    val directory = File(activity.cacheDir, "updates")
    MethodChannel(messenger, "kitchentable/updates").setMethodCallHandler { call, result ->
        try {
            val installed = pm.getPackageInfo(activity.packageName, PackageManager.GET_SIGNATURES)
            when (call.method) {
                "installed" -> result.success(mapOf(
                    "code" to PackageInfoCompat.getLongVersionCode(installed),
                    "name" to installed.versionName
                ))
                "directory" -> {
                    if (!directory.isDirectory && !directory.mkdirs()) {
                        result.error("cache", "Недостаточно места для обновления.", null)
                    } else {
                        result.success(directory.absolutePath)
                    }
                }
                "verify" -> {
                    val code = (call.arguments as Number).toLong()
                    thread(name = "verify-update-apk") {
                        val error = try {
                            val apk = File(directory, "update.apk")
                            val candidate = pm.getPackageArchiveInfo(apk.path, PackageManager.GET_SIGNATURES)
                            when {
                                candidate == null || candidate.packageName != activity.packageName ||
                                    PackageInfoCompat.getLongVersionCode(candidate) != code ||
                                    code <= PackageInfoCompat.getLongVersionCode(installed) ->
                                    "Этот APK не подходит для обновления KitchenTable."
                                candidate.signatures.isNullOrEmpty() ||
                                    candidate.signatures?.toSet() != installed.signatures?.toSet() ->
                                    "Подпись APK отличается от подписи установленной сборки."
                                else -> null
                            }
                        } catch (error: Exception) {
                            "Не удалось проверить подпись APK."
                        }
                        activity.runOnUiThread {
                            if (error == null) result.success(null)
                            else result.error("archive", error, null)
                        }
                    }
                }
                "install" -> {
                    val apk = File(directory, "update.apk")
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O && !pm.canRequestPackageInstalls()) {
                        activity.startActivity(Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,
                            Uri.parse("package:${activity.packageName}")))
                        result.success("permission")
                    } else {
                        val uri = FileProvider.getUriForFile(activity, "${activity.packageName}.updates", apk)
                        activity.startActivity(Intent(Intent.ACTION_VIEW)
                            .setDataAndType(uri, "application/vnd.android.package-archive")
                            .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION))
                        result.success("installer")
                    }
                }
                else -> result.notImplemented()
            }
        } catch (error: ActivityNotFoundException) {
            result.error("unavailable", "Установщик Android недоступен.", null)
        } catch (error: SecurityException) {
            result.error("permission", "Android запретил установку из этого приложения.", null)
        }
    }
}
