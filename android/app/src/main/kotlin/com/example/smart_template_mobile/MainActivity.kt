package com.convert2file.app

import android.content.ClipData
import android.content.Intent
import android.net.Uri
import androidx.core.content.FileProvider
import java.io.File
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val channelName = "convert2file/app_share"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "getInstalledApkPath" -> result.success(applicationInfo.publicSourceDir)
                    "shareApk" -> {
                        val apkPath = call.argument<String>("apkPath")
                        if (apkPath.isNullOrBlank()) {
                            result.error("missing_apk_path", "APK path is required.", null)
                            return@setMethodCallHandler
                        }

                        val apkFile = File(apkPath)
                        if (!apkFile.exists()) {
                            result.error("apk_not_found", "APK file was not found.", apkPath)
                            return@setMethodCallHandler
                        }

                        try {
                            val apkUri: Uri = FileProvider.getUriForFile(
                                this,
                                "${applicationContext.packageName}.fileprovider",
                                apkFile
                            )
                            val shareIntent = Intent(Intent.ACTION_SEND).apply {
                                type = "application/vnd.android.package-archive"
                                putExtra(Intent.EXTRA_STREAM, apkUri)
                                putExtra(Intent.EXTRA_SUBJECT, "Convert2File APK")
                                putExtra(
                                    Intent.EXTRA_TEXT,
                                    "Install Convert2File from the attached APK file."
                                )
                                clipData = ClipData.newUri(
                                    contentResolver,
                                    "Convert2File-installable.apk",
                                    apkUri
                                )
                                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                            }
                            startActivity(
                                Intent.createChooser(shareIntent, "Share Convert2File APK")
                            )
                            result.success(true)
                        } catch (e: Exception) {
                            result.error("share_apk_failed", e.message, null)
                        }
                    }
                    else -> result.notImplemented()
                }
            }
    }
}
