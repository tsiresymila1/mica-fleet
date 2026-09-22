package com.radoran.mica_fleet

import android.Manifest
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.database.sqlite.SQLiteDatabase
import android.location.Location
import android.location.LocationListener
import android.location.LocationManager
import android.os.Build
import android.os.IBinder
import androidx.core.app.ActivityCompat
import androidx.core.app.NotificationCompat
import androidx.core.content.ContextCompat
import java.io.File
import kotlin.math.*

class TripTrackingService : Service(), LocationListener {
    private lateinit var locationManager: LocationManager
    private var sessionId: String? = null
    private var anchor: Sample? = null
    private var previous: Sample? = null
    private val pending = mutableListOf<Sample>()

    override fun onCreate() {
        super.onCreate()
        locationManager = getSystemService(LOCATION_SERVICE) as LocationManager
        createNotificationChannel()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val requested = intent?.getStringExtra(EXTRA_SESSION)
        sessionId = requested ?: preferences(this).getString(PREF_SESSION, null)
        val id = sessionId
        if (id.isNullOrBlank()) {
            stopSelf()
            return START_NOT_STICKY
        }
        preferences(this).edit().putString(PREF_SESSION, id).apply()
        startForeground(NOTIFICATION_ID, notification(id))
        loadAnchor(id)
        startLocations()
        return START_STICKY
    }

    override fun onLocationChanged(location: Location) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S && location.isMock) return
        @Suppress("DEPRECATION")
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.S && location.isFromMockProvider) return
        val accuracy = location.accuracy.toDouble()
        val sample = Sample(
            location.latitude, location.longitude, accuracy,
            location.time / 1000,
            if (location.hasSpeed()) location.speed.toDouble() else null,
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O && location.hasSpeedAccuracy())
                location.speedAccuracyMetersPerSecond.toDouble() else null,
        )
        if (!sample.valid() || !shouldSave(sample)) return
        val id = sessionId ?: return
        if (insert(id, sample)) {
            anchor = sample
            previous = sample
            pending.clear()
        }
    }

    override fun onDestroy() {
        locationManager.removeUpdates(this)
        super.onDestroy()
    }

    override fun onBind(intent: Intent?): IBinder? = null

    private fun startLocations() {
        if (ActivityCompat.checkSelfPermission(this, Manifest.permission.ACCESS_FINE_LOCATION) !=
            PackageManager.PERMISSION_GRANTED &&
            ActivityCompat.checkSelfPermission(this, Manifest.permission.ACCESS_COARSE_LOCATION) !=
            PackageManager.PERMISSION_GRANTED) {
            stopSelf()
            return
        }
        locationManager.removeUpdates(this)
        runCatching {
            locationManager.requestLocationUpdates(LocationManager.GPS_PROVIDER, 3000L, 0f, this)
        }
        runCatching {
            locationManager.requestLocationUpdates(LocationManager.NETWORK_PROVIDER, 3000L, 0f, this)
        }
    }

    private fun shouldSave(current: Sample): Boolean {
        val last = previous
        if (last != null) {
            if (current.seconds <= last.seconds) return false
            val elapsed = (current.seconds - last.seconds).toDouble()
            val minimumTravel = max(0.0, distance(last, current) - uncertainty(last, current))
            if (minimumTravel / elapsed > 45.0) {
                pending.clear()
                return false
            }
        }
        previous = current
        val saved = anchor ?: return true
        if (current.speed != null && current.speedAccuracy != null &&
            current.speedAccuracy > 0 && current.speedAccuracy <= 1 &&
            current.speed + current.speedAccuracy <= .3) {
            pending.clear()
            return false
        }
        if (distance(saved, current) < 8.0) {
            pending.clear()
            return false
        }
        if (pending.isNotEmpty()) {
            val first = pending.first()
            val expired = current.seconds - first.seconds > 15
            val a = distance(saved, first)
            val b = distance(saved, current)
            val c = distance(first, current)
            if (expired || a * a + b * b - c * c < 0) pending.clear()
        }
        pending.add(current)
        while (pending.size > 6) pending.removeAt(0)
        val clear = distance(saved, current) >= uncertainty(saved, current)
        return if (clear) pending.size >= 2
        else pending.size >= 3 && distance(pending.first(), current) >= 3
    }

    private fun loadAnchor(id: String) {
        anchor = null
        previous = null
        pending.clear()
        database()?.use { db ->
            db.rawQuery(
                "SELECT lat, lon, captured_at FROM trajet_points WHERE chargement_id = ? " +
                    "ORDER BY captured_at DESC LIMIT 1", arrayOf(id)
            ).use { cursor ->
                if (cursor.moveToFirst()) {
                    anchor = Sample(cursor.getDouble(0), cursor.getDouble(1), 25.0,
                        cursor.getLong(2), null, null)
                    previous = anchor
                }
            }
        }
    }

    private fun insert(id: String, point: Sample): Boolean = runCatching {
        database()?.use { db ->
            db.execSQL(
                "INSERT INTO trajet_points (chargement_id, lat, lon, captured_at, simule) " +
                    "VALUES (?, ?, ?, ?, 0)",
                arrayOf<Any>(id, point.lat, point.lon, point.seconds),
            )
        } ?: return false
        true
    }.getOrDefault(false)

    private fun database(): SQLiteDatabase? {
        val file = File(filesDir.parentFile, "app_flutter/mica_fleet.db")
        if (!file.exists()) return null
        return SQLiteDatabase.openDatabase(file.path, null, SQLiteDatabase.OPEN_READWRITE)
    }

    private fun notification(id: String) = NotificationCompat.Builder(this, CHANNEL_ID)
        .setSmallIcon(applicationInfo.icon)
        .setContentTitle("MICA — suivi du trajet")
        .setContentText("Session $id en cours")
        .setOngoing(true)
        .setOnlyAlertOnce(true)
        .setContentIntent(PendingIntent.getActivity(
            this, 0, packageManager.getLaunchIntentForPackage(packageName),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )).build()

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID, "Suivi du trajet", NotificationManager.IMPORTANCE_LOW,
            ).apply { description = "Position enregistrée pendant un transport en cours" }
            getSystemService(NotificationManager::class.java).createNotificationChannel(channel)
        }
    }

    private data class Sample(
        val lat: Double, val lon: Double, val accuracy: Double, val seconds: Long,
        val speed: Double?, val speedAccuracy: Double?,
    ) {
        fun valid() = lat.isFinite() && lat in -90.0..90.0 &&
            lon.isFinite() && lon in -180.0..180.0 &&
            accuracy.isFinite() && accuracy > 0 && accuracy <= 25
    }

    private fun uncertainty(a: Sample, b: Sample) = hypot(a.accuracy, b.accuracy)
    private fun distance(a: Sample, b: Sample): Double {
        val p1 = Math.toRadians(a.lat)
        val p2 = Math.toRadians(b.lat)
        val dp = Math.toRadians(b.lat - a.lat)
        val dl = Math.toRadians(b.lon - a.lon)
        val h = sin(dp / 2).pow(2) + cos(p1) * cos(p2) * sin(dl / 2).pow(2)
        return 6371000.0 * 2 * atan2(sqrt(h), sqrt(1 - h))
    }

    companion object {
        private const val CHANNEL_ID = "mica_trip_tracking"
        private const val NOTIFICATION_ID = 75416
        private const val EXTRA_SESSION = "chargement_id"
        private const val PREFS = "trip_tracking"
        private const val PREF_SESSION = "active_session"
        private const val ACTION_STOP = "net.radoran.mica.STOP_TRIP_TRACKING"

        private fun preferences(context: Context) =
            context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)

        fun hasActiveSession(context: Context) =
            !preferences(context).getString(PREF_SESSION, null).isNullOrBlank()

        fun start(context: Context, id: String) {
            preferences(context).edit().putString(PREF_SESSION, id).apply()
            val intent = Intent(context, TripTrackingService::class.java)
                .putExtra(EXTRA_SESSION, id)
            ContextCompat.startForegroundService(context, intent)
        }

        fun stop(context: Context) {
            preferences(context).edit().remove(PREF_SESSION).apply()
            context.stopService(Intent(context, TripTrackingService::class.java))
        }

        fun restartIfNeeded(context: Context) {
            val id = preferences(context).getString(PREF_SESSION, null) ?: return
            start(context, id)
        }
    }
}
