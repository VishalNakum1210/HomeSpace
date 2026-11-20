package com.homespace.homespace

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.util.Log

/**
 * Ensures AutoBackupJobService is registered and active across device reboots,
 * app updates, and power events.
 */
class AutoBackupBootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context?, intent: Intent?) {
        if (context == null) return
        Log.d(AutoBackupJobService.TAG, "AutoBackupBootReceiver received action: ${intent?.action}")

        when (intent?.action) {
            Intent.ACTION_BOOT_COMPLETED,
            Intent.ACTION_MY_PACKAGE_REPLACED,
            Intent.ACTION_POWER_CONNECTED -> {
                AutoBackupJobService.schedule(context)
            }
        }
    }
}
