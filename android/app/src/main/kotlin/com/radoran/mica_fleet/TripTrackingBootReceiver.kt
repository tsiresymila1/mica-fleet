package com.radoran.mica_fleet

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

class TripTrackingBootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action == Intent.ACTION_BOOT_COMPLETED) {
            TripTrackingService.restartIfNeeded(context)
        }
    }
}
