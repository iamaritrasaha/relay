package org.localsend.localsend_app.continuity

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.os.BatteryManager

/**
 * Real battery state from the platform's own broadcast.
 *
 * ACTION_BATTERY_CHANGED is sticky, so the current value is available without
 * polling, and the receiver only wakes this process when the system already
 * decided something changed. No timer, no wake lock.
 */
class AndroidBatteryProvider(private val context: Context) : BatteryProvider {

    override fun snapshot(): BatterySnapshot {
        val intent = context.registerReceiver(null, IntentFilter(Intent.ACTION_BATTERY_CHANGED))
            ?: return BatterySnapshot(percentage = null, charging = ChargingState.UNKNOWN)
        return intent.toSnapshot()
    }

    override fun observe(onChange: (BatterySnapshot) -> Unit): AutoCloseable {
        val receiver = object : BroadcastReceiver() {
            override fun onReceive(context: Context?, intent: Intent?) {
                intent?.let { onChange(it.toSnapshot()) }
            }
        }
        context.registerReceiver(receiver, IntentFilter(Intent.ACTION_BATTERY_CHANGED))
        return AutoCloseable {
            runCatching { context.unregisterReceiver(receiver) }
        }
    }

    private fun Intent.toSnapshot(): BatterySnapshot {
        val level = getIntExtra(BatteryManager.EXTRA_LEVEL, -1)
        val scale = getIntExtra(BatteryManager.EXTRA_SCALE, -1)
        // A missing level stays missing rather than being reported as 0%.
        val percentage = if (level >= 0 && scale > 0) (level * 100) / scale else null
        val charging = when (getIntExtra(BatteryManager.EXTRA_STATUS, BatteryManager.BATTERY_STATUS_UNKNOWN)) {
            BatteryManager.BATTERY_STATUS_CHARGING -> ChargingState.CHARGING
            BatteryManager.BATTERY_STATUS_FULL -> ChargingState.FULL
            BatteryManager.BATTERY_STATUS_DISCHARGING -> ChargingState.DISCHARGING
            BatteryManager.BATTERY_STATUS_NOT_CHARGING -> ChargingState.NOT_CHARGING
            else -> ChargingState.UNKNOWN
        }
        // Voltage, current and temperature are deliberately not read: normal
        // continuity has no use for them and they are extra telemetry to leak.
        return BatterySnapshot(percentage = percentage, charging = charging)
    }
}
