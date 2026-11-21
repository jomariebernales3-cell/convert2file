package com.convert2file.app

import android.Manifest
import android.content.ClipData
import android.content.Intent
import android.content.res.Configuration
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.RectF
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.SystemClock
import android.view.View
import android.view.ViewGroup
import android.view.WindowManager
import android.widget.FrameLayout
import androidx.core.content.FileProvider
import java.io.File
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val channelName = "convert2file/app_share"
    private val offlineAiChannelName = "convert2file/offline_ai_task"
    private val startupSplashChannelName = "convert2file/startup_splash"
    private var permissionRequestResult: MethodChannel.Result? = null
    private var offlineAiTaskActive = false
    private var startupSplashView: StartupSplashView? = null

    override fun onCreate(savedInstanceState: android.os.Bundle?) {
        super.onCreate(savedInstanceState)
        val content = findViewById<FrameLayout>(android.R.id.content)
        val splash = StartupSplashView(this)
        startupSplashView = splash
        content.addView(
            splash,
            FrameLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.MATCH_PARENT
            )
        )
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "getInstalledApkPath" -> {
                        val versionName = packageManager
                            .getPackageInfo(packageName, 0)
                            .versionName
                        result.success(
                            mapOf(
                                "path" to applicationInfo.publicSourceDir,
                                "versionName" to versionName
                            )
                        )
                    }
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
                                "com.convert2file.app.fileprovider",
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

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, offlineAiChannelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "requestNotificationPermission" -> requestNotificationPermission(result)
                    "start" -> {
                        offlineAiTaskActive = true
                        window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                        try {
                            OfflineAiTaskService.start(
                                this,
                                call.argument<String>("title") ?: "Offline AI is working"
                            )
                            result.success(true)
                        } catch (e: Exception) {
                            offlineAiTaskActive = false
                            window.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                            result.error("offline_ai_start_failed", e.message, null)
                        }
                    }
                    "updateStatus" -> {
                        OfflineAiTaskService.update(
                            this,
                            call.argument<String>("status") ?: "Still working..."
                        )
                        result.success(true)
                    }
                    "finish" -> {
                        offlineAiTaskActive = false
                        window.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                        OfflineAiTaskService.finish(
                            this,
                            call.argument<Boolean>("success") ?: true,
                            call.argument<String>("message") ?: "Offline AI finished."
                        )
                        result.success(true)
                    }
                    "cancel" -> {
                        offlineAiTaskActive = false
                        window.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                        OfflineAiTaskService.cancel(this)
                        result.success(true)
                    }
                    else -> result.notImplemented()
                }
            }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, startupSplashChannelName)
            .setMethodCallHandler { call, result ->
                if (call.method != "dismiss") {
                    result.notImplemented()
                    return@setMethodCallHandler
                }
                startupSplashView?.let { splash ->
                    (splash.parent as? ViewGroup)?.removeView(splash)
                }
                startupSplashView = null
                result.success(null)
            }
    }

    private fun requestNotificationPermission(result: MethodChannel.Result) {
        if (Build.VERSION.SDK_INT < 33 ||
            checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) ==
            PackageManager.PERMISSION_GRANTED
        ) {
            result.success(true)
            return
        }
        if (permissionRequestResult != null) {
            result.error("permission_request_in_progress", "Notification permission is already being requested.", null)
            return
        }
        permissionRequestResult = result
        requestPermissions(
            arrayOf(Manifest.permission.POST_NOTIFICATIONS),
            NOTIFICATION_PERMISSION_REQUEST
        )
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == NOTIFICATION_PERMISSION_REQUEST) {
            permissionRequestResult?.success(
                grantResults.firstOrNull() == PackageManager.PERMISSION_GRANTED
            )
            permissionRequestResult = null
        }
    }

    override fun onPause() {
        window.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        super.onPause()
    }

    override fun onResume() {
        super.onResume()
        if (offlineAiTaskActive) {
            window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        }
    }

    companion object {
        private const val NOTIFICATION_PERMISSION_REQUEST = 8303
    }
}

private class StartupSplashView(context: android.content.Context) : View(context) {
    private val nightMode =
        (resources.configuration.uiMode and Configuration.UI_MODE_NIGHT_MASK) ==
            Configuration.UI_MODE_NIGHT_YES
    private val backgroundColor = if (nightMode) Color.BLACK else Color.WHITE
    private val trackColor = if (nightMode) Color.rgb(58, 58, 58) else Color.rgb(224, 224, 224)
    private val arcColor = if (nightMode) Color.WHITE else Color.BLACK
    private val logo: Bitmap = BitmapFactory.decodeResource(resources, R.drawable.splash_logo)
    private val logoPaint = Paint(Paint.ANTI_ALIAS_FLAG or Paint.FILTER_BITMAP_FLAG)
    private val trackPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = trackColor
        style = Paint.Style.STROKE
    }
    private val arcPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = arcColor
        style = Paint.Style.STROKE
        strokeCap = Paint.Cap.ROUND
    }
    private val circleBounds = RectF()
    private val logoBounds = RectF()

    init {
        isClickable = true
        isFocusable = true
        setBackgroundColor(backgroundColor)
    }

    override fun onDraw(canvas: Canvas) {
        super.onDraw(canvas)
        val diameter = minOf(width * 0.46f, 260f * resources.displayMetrics.density)
        val stroke = diameter * 0.065f
        val radius = (diameter - stroke) / 2f
        val centerX = width / 2f
        val centerY = height / 2f
        circleBounds.set(centerX - radius, centerY - radius, centerX + radius, centerY + radius)
        trackPaint.strokeWidth = stroke
        arcPaint.strokeWidth = stroke
        canvas.drawCircle(centerX, centerY, radius, trackPaint)

        val progress = (SystemClock.uptimeMillis() % 1100L) / 1100f
        canvas.drawArc(circleBounds, 50f + progress * 360f, 72f, false, arcPaint)

        val logoSize = diameter * 0.55f
        logoBounds.set(
            centerX - logoSize / 2f,
            centerY - logoSize / 2f,
            centerX + logoSize / 2f,
            centerY + logoSize / 2f
        )
        canvas.drawBitmap(logo, null, logoBounds, logoPaint)
        if (isAttachedToWindow) postInvalidateOnAnimation()
    }
}
