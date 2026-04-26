package com.negern.negern

import android.app.Service
import android.content.Intent
import android.net.VpnService
import android.os.IBinder
import android.util.Log

/**
 * Заглушка Android VpnService. В следующей итерации:
 *  - создаёт TUN через VpnService.Builder,
 *  - передаёт fd в Go-библиотеку (xray-bridge / awg-bridge),
 *  - вызывает protect() для upstream-сокетов.
 *
 * Сейчас только логирует команды и поддерживает жизненный цикл сервиса, чтобы
 * UI-скелет мог проверить путь prepare/start/stop.
 */
class NegernVpnService : VpnService() {

    companion object {
        private const val TAG = "NegernVpnService"
        @Volatile var runningEngine: Int? = null
            private set
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val engine = intent?.getIntExtra("engine", -1) ?: -1
        Log.i(TAG, "onStartCommand engine=$engine")
        runningEngine = if (engine >= 0) engine else null
        // TODO: Builder().addAddress(...).addRoute(...).establish()
        // TODO: Go.StartVless(configJson, tunFd) или Go.StartAwg(configIni, tunFd)
        return START_STICKY
    }

    override fun onDestroy() {
        Log.i(TAG, "onDestroy")
        runningEngine = null
        // TODO: Go.Stop()
        super.onDestroy()
    }

    override fun onBind(intent: Intent?): IBinder? = null
}

