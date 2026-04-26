package com.negern.negern

import android.app.Activity
import android.content.Intent
import android.net.VpnService
import android.os.Handler
import android.os.Looper
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

/**
 * MethodChannel-хост канала `negern/vpn` для Android.
 * Работает как заготовка: подтверждает команды и эмулирует статус через
 * EventChannel `negern/vpn/events`, чтобы Flutter-слой мог видеть реальный
 * connected/disconnected без полноценного VPN-ядра.
 */
class MainActivity : FlutterActivity() {
    companion object {
        private const val METHOD = "negern/vpn"
        private const val EVENTS = "negern/vpn/events"
        private const val REQ_VPN = 1001
    }

    private var eventsSink: EventChannel.EventSink? = null
    private var runningEngine: Int? = null
    private var pendingPrepare: MethodChannel.Result? = null
    private val handler = Handler(Looper.getMainLooper())

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val messenger = flutterEngine.dartExecutor.binaryMessenger

        MethodChannel(messenger, METHOD).setMethodCallHandler { call, result ->
            when (call.method) {
                "prepare" -> {
                    val intent = VpnService.prepare(this)
                    if (intent == null) {
                        result.success(true)
                    } else {
                        pendingPrepare = result
                        startActivityForResult(intent, REQ_VPN)
                    }
                }
                "start" -> {
                    val engine = call.argument<Int>("engine") ?: -1
                    runningEngine = engine
                    val svc = Intent(this, NegernVpnService::class.java)
                        .putExtra("engine", engine)
                    startService(svc)
                    emitStatus("connecting", engine, 0, 0)
                    handler.postDelayed({
                        emitStatus("connected", engine, 0, 0)
                    }, 300)
                    result.success(null)
                }
                "stop" -> {
                    stopService(Intent(this, NegernVpnService::class.java))
                    emitStatus("disconnecting", runningEngine, 0, 0)
                    handler.postDelayed({
                        runningEngine = null
                        emitStatus("disconnected", null, 0, 0)
                    }, 200)
                    result.success(null)
                }
                "status" -> {
                    val map = mutableMapOf<String, Any?>(
                        "state" to if (runningEngine == null) "disconnected" else "connected",
                        "engine" to runningEngine,
                        "upload" to 0,
                        "download" to 0,
                    )
                    result.success(map)
                }
                else -> result.notImplemented()
            }
        }

        EventChannel(messenger, EVENTS).setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                eventsSink = events
            }
            override fun onCancel(arguments: Any?) {
                eventsSink = null
            }
        })
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        if (requestCode == REQ_VPN) {
            pendingPrepare?.success(resultCode == Activity.RESULT_OK)
            pendingPrepare = null
        }
        super.onActivityResult(requestCode, resultCode, data)
    }

    private fun emitStatus(state: String, engine: Int?, up: Int, down: Int) {
        val map = mapOf(
            "state" to state,
            "engine" to engine,
            "upload" to up,
            "download" to down,
        )
        eventsSink?.success(map)
    }
}

