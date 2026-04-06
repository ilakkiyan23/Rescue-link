package com.example.rescue_link

import android.Manifest
import android.content.pm.PackageManager
import android.os.Build
import android.telephony.SmsManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import androidx.core.content.ContextCompat

class MainActivity : FlutterActivity() {
	private val smsChannelName = "rescue_link/direct_sms"

	override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
		super.configureFlutterEngine(flutterEngine)
		MethodChannel(flutterEngine.dartExecutor.binaryMessenger, smsChannelName).setMethodCallHandler { call, result ->
			when (call.method) {
				"sendDirectSms" -> {
					val recipient = call.argument<String>("recipient")?.trim()
					val message = call.argument<String>("message")?.trim()
					if (recipient.isNullOrEmpty() || message.isNullOrEmpty()) {
						result.error("invalid_args", "Recipient and message are required", null)
						return@setMethodCallHandler
					}
					if (ContextCompat.checkSelfPermission(this, Manifest.permission.SEND_SMS) != PackageManager.PERMISSION_GRANTED) {
						result.error("permission_denied", "SEND_SMS permission not granted", null)
						return@setMethodCallHandler
					}
					try {
						val smsManager = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
							getSystemService(SmsManager::class.java)
						} else {
							@Suppress("DEPRECATION")
							SmsManager.getDefault()
						}
						smsManager.sendTextMessage(recipient, null, message, null, null)
						result.success(true)
					} catch (error: Exception) {
						result.error("send_failed", error.message, null)
					}
				}
				else -> result.notImplemented()
			}
		}
	}
}
