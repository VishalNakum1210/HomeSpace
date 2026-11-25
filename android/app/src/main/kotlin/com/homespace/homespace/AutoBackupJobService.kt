package com.homespace.homespace

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.job.JobInfo
import android.app.job.JobParameters
import android.app.job.JobScheduler
import android.app.job.JobService
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.SharedPreferences
import android.content.pm.PackageManager
import android.net.ConnectivityManager
import android.net.NetworkCapabilities
import android.os.BatteryManager
import android.os.Build
import android.provider.MediaStore
import android.util.Log
import androidx.core.app.NotificationCompat
import androidx.core.content.ContextCompat
import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import java.net.HttpURLConnection
import java.net.InetAddress
import java.net.URL
import java.net.URLEncoder
import java.security.KeyStore
import java.security.MessageDigest
import java.security.cert.X509Certificate
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.TimeZone
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicBoolean
import javax.net.ssl.HttpsURLConnection
import javax.net.ssl.SSLContext
import javax.net.ssl.SSLSocketFactory
import javax.net.ssl.TrustManager
import javax.net.ssl.TrustManagerFactory
import javax.net.ssl.X509TrustManager

/**
 * Native Android JobService for reliable Google-Photos-like background auto backup.
 * 
 * Uses JobScheduler with TriggerContentUri to wake up immediately when the Camera
 * app captures a new photo/video, even if HomeSpace is not running in the background.
 */
class AutoBackupJobService : JobService() {

    companion object {
        const val TAG = "HomeSpaceAutoBackup"
        const val CONTENT_TRIGGER_JOB_ID = 9001
        const val PERIODIC_BACKUP_JOB_ID = 9002

        const val PREFS_NAME = "homespace_backup_prefs"
        const val KEY_SERVER_URI = "server_uri"
        const val KEY_AUTH_TOKEN = "auth_token"
        const val KEY_ENABLED_FOLDERS = "enabled_folders"
        const val KEY_UPLOADED_ITEMS = "uploaded_items"
        const val KEY_IGNORED_OR_DELETED_ITEMS = "ignored_or_deleted_items"
        const val KEY_BACKUP_START_TIME = "backup_start_time"
        const val KEY_FOLDER_START_TIMES = "folder_start_times"
        const val KEY_WIFI_ONLY = "wifi_only"
        const val KEY_REQUIRE_CHARGING = "require_charging"
        const val KEY_TRUSTED_CERT_PINS = "trusted_cert_pins"

        private const val NOTIFICATION_CHANNEL_ID = "homespace_auto_backup"
        private const val NOTIFICATION_ID = 9003

        private val executor = Executors.newSingleThreadExecutor()

        fun hasAuthConfig(context: Context): Boolean {
            val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            val server = prefs.getString(KEY_SERVER_URI, null)
            val token = prefs.getString(KEY_AUTH_TOKEN, null)
            return !server.isNullOrBlank() && !token.isNullOrBlank()
        }

        fun cancelAll(context: Context) {
            val jobScheduler = context.getSystemService(Context.JOB_SCHEDULER_SERVICE) as? JobScheduler ?: return
            jobScheduler.cancel(CONTENT_TRIGGER_JOB_ID)
            jobScheduler.cancel(PERIODIC_BACKUP_JOB_ID)
            Log.d(TAG, "Cancelled all background auto-backup jobs.")
        }

        fun isWifiConnected(context: Context): Boolean {
            val cm = context.getSystemService(Context.CONNECTIVITY_SERVICE) as? ConnectivityManager ?: return true
            val network = cm.activeNetwork ?: return false
            val capabilities = cm.getNetworkCapabilities(network) ?: return false
            return capabilities.hasTransport(NetworkCapabilities.TRANSPORT_WIFI) ||
                   capabilities.hasCapability(NetworkCapabilities.NET_CAPABILITY_NOT_METERED)
        }

        fun isDeviceCharging(context: Context): Boolean {
            val ifilter = IntentFilter(Intent.ACTION_BATTERY_CHANGED)
            val batteryStatus = context.registerReceiver(null, ifilter)
            val status = batteryStatus?.getIntExtra(BatteryManager.EXTRA_STATUS, -1) ?: -1
            return status == BatteryManager.BATTERY_STATUS_CHARGING || status == BatteryManager.BATTERY_STATUS_FULL
        }

        fun markItemUploaded(context: Context, filename: String, size: Long = 0L) {
            val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            val current = prefs.getStringSet(KEY_UPLOADED_ITEMS, null)?.toMutableSet() ?: mutableSetOf()
            if (size > 0L) {
                current.add("${filename.lowercase()}_$size")
            } else {
                current.add(filename.lowercase())
            }
            prefs.edit().putStringSet(KEY_UPLOADED_ITEMS, current).apply()
        }

        fun markMediaIgnoredOrDeleted(context: Context, filenames: List<String>) {
            val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            val current = prefs.getStringSet(KEY_IGNORED_OR_DELETED_ITEMS, null)?.toMutableSet() ?: mutableSetOf()
            for (fn in filenames) {
                if (fn.isNotBlank()) {
                    current.add(fn.lowercase().trim())
                }
            }
            prefs.edit().putStringSet(KEY_IGNORED_OR_DELETED_ITEMS, current).apply()
        }

        fun unmarkMediaIgnoredOrDeleted(context: Context, filenames: List<String>) {
            val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            val current = prefs.getStringSet(KEY_IGNORED_OR_DELETED_ITEMS, null)?.toMutableSet() ?: mutableSetOf()
            for (fn in filenames) {
                if (fn.isNotBlank()) {
                    current.remove(fn.lowercase().trim())
                }
            }
            prefs.edit().putStringSet(KEY_IGNORED_OR_DELETED_ITEMS, current).apply()
        }

        fun getIgnoredOrDeletedItems(context: Context): List<String> {
            val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            return prefs.getStringSet(KEY_IGNORED_OR_DELETED_ITEMS, null)?.toList() ?: emptyList()
        }

        fun scheduleTriggerJob(context: Context) {
            if (!hasAuthConfig(context)) return
            val jobScheduler = context.getSystemService(Context.JOB_SCHEDULER_SERVICE) as? JobScheduler ?: return
            val component = ComponentName(context, AutoBackupJobService::class.java)
            val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            val wifiOnly = prefs.getBoolean(KEY_WIFI_ONLY, false)
            val requireCharging = prefs.getBoolean(KEY_REQUIRE_CHARGING, false)
            val networkType = if (wifiOnly) JobInfo.NETWORK_TYPE_UNMETERED else JobInfo.NETWORK_TYPE_ANY

            try {
                val triggerBuilder = JobInfo.Builder(CONTENT_TRIGGER_JOB_ID, component)
                    .addTriggerContentUri(
                        JobInfo.TriggerContentUri(
                            MediaStore.Images.Media.EXTERNAL_CONTENT_URI,
                            JobInfo.TriggerContentUri.FLAG_NOTIFY_FOR_DESCENDANTS
                        )
                    )
                    .addTriggerContentUri(
                        JobInfo.TriggerContentUri(
                            MediaStore.Video.Media.EXTERNAL_CONTENT_URI,
                            JobInfo.TriggerContentUri.FLAG_NOTIFY_FOR_DESCENDANTS
                        )
                    )
                    .setTriggerContentUpdateDelay(1500)
                    .setTriggerContentMaxDelay(4000)
                    .setRequiredNetworkType(networkType)
                    .setRequiresCharging(requireCharging)

                val result = jobScheduler.schedule(triggerBuilder.build())
                Log.d(TAG, "Scheduled ContentUri trigger job (id=$CONTENT_TRIGGER_JOB_ID, wifiOnly=$wifiOnly, charging=$requireCharging, result=$result)")
            } catch (e: Exception) {
                Log.e(TAG, "Failed to schedule ContentUri trigger job", e)
            }
        }

        /**
         * Schedules both the real-time ContentUri trigger job and the 15-minute periodic fallback job
         * without resetting the periodic timer if constraints are unchanged.
         */
        fun schedule(context: Context) {
            if (!hasAuthConfig(context)) {
                cancelAll(context)
                return
            }
            scheduleTriggerJob(context)

            val jobScheduler = context.getSystemService(Context.JOB_SCHEDULER_SERVICE) as? JobScheduler ?: return
            val component = ComponentName(context, AutoBackupJobService::class.java)

            val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            val wifiOnly = prefs.getBoolean(KEY_WIFI_ONLY, false)
            val requireCharging = prefs.getBoolean(KEY_REQUIRE_CHARGING, false)
            val networkType = if (wifiOnly) JobInfo.NETWORK_TYPE_UNMETERED else JobInfo.NETWORK_TYPE_ANY

            val existingPeriodic = jobScheduler.allPendingJobs.firstOrNull { it.id == PERIODIC_BACKUP_JOB_ID }
            if (existingPeriodic != null &&
                existingPeriodic.networkType == networkType &&
                existingPeriodic.isRequireCharging == requireCharging
            ) {
                return
            }

            try {
                val periodicBuilder = JobInfo.Builder(PERIODIC_BACKUP_JOB_ID, component)
                    .setPeriodic(15 * 60 * 1000)
                    .setRequiredNetworkType(networkType)
                    .setRequiresCharging(requireCharging)
                    .setPersisted(true)

                val result = jobScheduler.schedule(periodicBuilder.build())
                Log.d(TAG, "Scheduled periodic backup job (id=$PERIODIC_BACKUP_JOB_ID, wifiOnly=$wifiOnly, charging=$requireCharging, result=$result)")
            } catch (_: Exception) {
                try {
                    val periodicBuilder = JobInfo.Builder(PERIODIC_BACKUP_JOB_ID, component)
                        .setPeriodic(15 * 60 * 1000)
                        .setRequiredNetworkType(networkType)
                        .setRequiresCharging(requireCharging)
                    jobScheduler.schedule(periodicBuilder.build())
                } catch (_: Exception) {}
            }
        }

        fun isScheduled(context: Context): Boolean {
            val jobScheduler = context.getSystemService(Context.JOB_SCHEDULER_SERVICE) as? JobScheduler ?: return false
            return jobScheduler.allPendingJobs.any { it.id == CONTENT_TRIGGER_JOB_ID }
        }

        /**
         * Replicates Dart's AutoBackupService.classifyMediaFolder logic 1:1.
         */
        fun classifyMediaFolder(filePath: String): String? {
            val lower = filePath.lowercase().replace('\\', '/')

            // Never backup HomeSpace downloaded photos/videos to prevent re-upload loops
            if (lower.contains("/pictures/homespace") || lower.contains("/movies/homespace")) {
                return null
            }

            // 1. Screenshots
            if (lower.contains("/screenshots") ||
                lower.contains("/screenshot") ||
                lower.substringAfterLast('/').startsWith("screenshot")) {
                return "screenshots"
            }

            // 2. WhatsApp Images and Videos
            if (lower.contains("whatsapp")) {
                return "whatsapp"
            }

            // 3. Downloads
            if (lower.contains("/download") || lower.contains("/downloads")) {
                return "downloads"
            }

            // 4. Camera (DCIM)
            if (lower.contains("/dcim/camera") ||
                lower.contains("/dcim/100andro") ||
                lower.contains("/dcim/100media") ||
                (lower.contains("/dcim") && !lower.contains("/dcim/facebook") && !lower.contains("/dcim/restored"))) {
                return "camera"
            }

            // 5. Pictures
            if (lower.contains("/pictures")) {
                return "pictures"
            }

            return null
        }
    }

    private val jobAborted = AtomicBoolean(false)

    override fun onStartJob(params: JobParameters?): Boolean {
        Log.d(TAG, "onStartJob triggered with id=${params?.jobId}")
        jobAborted.set(false)

        // Re-arm only the ContentUri trigger so any subsequent photo taken will also trigger
        if (params?.jobId == CONTENT_TRIGGER_JOB_ID) {
            scheduleTriggerJob(applicationContext)
        }

        executor.execute {
            try {
                processAutoBackup(params)
            } catch (e: Exception) {
                Log.e(TAG, "Error in background auto backup processing", e)
            } finally {
                cancelNotification()
                if (params != null) {
                    jobFinished(params, false)
                }
            }
        }

        return true // Work is running asynchronously
    }

    override fun onStopJob(params: JobParameters?): Boolean {
        Log.d(TAG, "onStopJob called for id=${params?.jobId}")
        jobAborted.set(true)
        cancelNotification()
        return true // Reschedule if aborted
    }

    private data class BackupConfig(
        val serverUri: String,
        val token: String,
        val enabledFolders: Set<String>,
        val backupStartTime: Long,
        val folderStartTimes: Map<String, Long>
    )

    private fun loadConfig(): BackupConfig? {
        val prefs = getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        var serverUri = prefs.getString(KEY_SERVER_URI, null)
        var token = prefs.getString(KEY_AUTH_TOKEN, null)
        val enabledFolders = prefs.getStringSet(KEY_ENABLED_FOLDERS, null)?.toMutableSet()
            ?: mutableSetOf("camera", "whatsapp")
        var backupStartTime = prefs.getLong(KEY_BACKUP_START_TIME, 0L)
        val folderStartTimes = mutableMapOf<String, Long>()

        // Load folderStartTimes JSON from prefs
        val rawFolderTimes = prefs.getString(KEY_FOLDER_START_TIMES, null)
        if (!rawFolderTimes.isNullOrEmpty()) {
            try {
                val json = JSONObject(rawFolderTimes)
                val keys = json.keys()
                while (keys.hasNext()) {
                    val k = keys.next()
                    folderStartTimes[k] = json.getLong(k)
                }
            } catch (_: Exception) {}
        }

        // Fallback 1: check app_flutter/homespace/session.json ONLY if not explicitly cleared
        if (!prefs.contains(KEY_AUTH_TOKEN) && (serverUri.isNullOrEmpty() || token.isNullOrEmpty())) {
            try {
                val dataDir = applicationInfo.dataDir
                val sessionFile = File(dataDir, "app_flutter/homespace/session.json")
                if (sessionFile.exists()) {
                    val json = JSONObject(sessionFile.readText())
                    if (token.isNullOrEmpty()) token = json.optString("token", "").ifEmpty { null }
                    if (serverUri.isNullOrEmpty()) serverUri = json.optString("serverUri", "").ifEmpty { null }
                }
            } catch (_: Exception) {}
        }

        // Do not fall back to any hardcoded external server URI
        if (serverUri.isNullOrBlank()) {
            Log.d(TAG, "AutoBackup skipped: no server URI configured.")
            return null
        }

        // Fallback 3: check backup_settings.json for folder switches, backupStartTime and enabledAt
        try {
            val dataDir = applicationInfo.dataDir
            val settingsFile = File(dataDir, "app_flutter/homespace/backup_settings.json")
            if (settingsFile.exists()) {
                val json = JSONObject(settingsFile.readText())
                val foldersArray = json.optJSONArray("folders")
                if (foldersArray != null) {
                    enabledFolders.clear()
                    for (i in 0 until foldersArray.length()) {
                        val item = foldersArray.getJSONObject(i)
                        val id = item.getString("id")
                        val enabled = item.optBoolean("enabled", false)
                        val enabledAt = item.optLong("enabledAt", 0L)
                        if (enabled) {
                            enabledFolders.add(id)
                            if (enabledAt > 0L && !folderStartTimes.containsKey(id)) {
                                folderStartTimes[id] = enabledAt
                            }
                        }
                    }
                }
                if (backupStartTime <= 0L) {
                    backupStartTime = json.optLong("backupStartTime", 0L)
                }
            }
        } catch (_: Exception) {}

        if (backupStartTime <= 0L) {
            backupStartTime = System.currentTimeMillis()
            prefs.edit().putLong(KEY_BACKUP_START_TIME, backupStartTime).apply()
        }

        if (token.isNullOrEmpty()) {
            Log.d(TAG, "AutoBackup skipped: user not authenticated yet.")
            return null
        }

        if (enabledFolders.isEmpty()) {
            Log.d(TAG, "AutoBackup skipped: no folders enabled for backup.")
            return null
        }

        return BackupConfig(
            serverUri = serverUri,
            token = token,
            enabledFolders = enabledFolders,
            backupStartTime = backupStartTime,
            folderStartTimes = folderStartTimes
        )
    }

    private fun hasStoragePermission(): Boolean {
        return if (Build.VERSION.SDK_INT >= 34) {
            ContextCompat.checkSelfPermission(this, android.Manifest.permission.READ_MEDIA_IMAGES) == PackageManager.PERMISSION_GRANTED ||
            ContextCompat.checkSelfPermission(this, android.Manifest.permission.READ_MEDIA_VIDEO) == PackageManager.PERMISSION_GRANTED ||
            ContextCompat.checkSelfPermission(this, android.Manifest.permission.READ_MEDIA_VISUAL_USER_SELECTED) == PackageManager.PERMISSION_GRANTED
        } else if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            ContextCompat.checkSelfPermission(this, android.Manifest.permission.READ_MEDIA_IMAGES) == PackageManager.PERMISSION_GRANTED ||
            ContextCompat.checkSelfPermission(this, android.Manifest.permission.READ_MEDIA_VIDEO) == PackageManager.PERMISSION_GRANTED
        } else {
            ContextCompat.checkSelfPermission(this, android.Manifest.permission.READ_EXTERNAL_STORAGE) == PackageManager.PERMISSION_GRANTED
        }
    }

    private data class KnownSignatures(
        val uploaded: MutableSet<String>,
        val ignored: MutableSet<String>
    )

    private fun getUploadedSignatures(prefs: SharedPreferences): KnownSignatures {
        val uploaded = prefs.getStringSet(KEY_UPLOADED_ITEMS, null)
            ?.map { it.lowercase() }
            ?.toMutableSet() ?: mutableSetOf()
        val ignored = prefs.getStringSet(KEY_IGNORED_OR_DELETED_ITEMS, null)
            ?.map { it.lowercase() }
            ?.toMutableSet() ?: mutableSetOf()

        // Also check deleted_signatures.json written by Dart app on explicit delete/trash
        try {
            val dataDir = applicationInfo.dataDir
            val delFile = File(dataDir, "app_flutter/homespace/deleted_signatures.json")
            if (delFile.exists()) {
                val arr = JSONArray(delFile.readText())
                for (i in 0 until arr.length()) {
                    val s = arr.optString(i, "")
                    if (s.isNotEmpty()) {
                        ignored.add(s.lowercase())
                    }
                }
            }
        } catch (_: Exception) {}

        return KnownSignatures(uploaded = uploaded, ignored = ignored)
    }

    private fun isAlreadyBackedUpOrIgnored(name: String, size: Long, known: KnownSignatures): Boolean {
        val lowerName = name.lowercase()
        val sizeKey = "${lowerName}_$size"
        if (known.ignored.contains(lowerName) || known.ignored.contains(sizeKey)) {
            return true
        }
        return known.uploaded.contains(sizeKey)
    }

    private fun markItemUploaded(prefs: SharedPreferences, filename: String, size: Long) {
        AutoBackupJobService.markItemUploaded(this, filename, size)
    }

    private data class CandidateMedia(
        val file: File,
        val filename: String,
        val mimeType: String,
        val size: Long,
        val takenAtIso: String
    )

    private fun processAutoBackup(params: JobParameters?) {
        val config = loadConfig() ?: return

        if (!hasStoragePermission()) {
            Log.w(TAG, "Storage permission not granted. Cannot scan media.")
            return
        }

        val prefs = getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        val wifiOnly = prefs.getBoolean(KEY_WIFI_ONLY, false)
        val requireCharging = prefs.getBoolean(KEY_REQUIRE_CHARGING, false)

        if (wifiOnly && !isWifiConnected(this)) {
            Log.d(TAG, "processAutoBackup: Wi-Fi only constraint enabled, but device is not connected to Wi-Fi. Skipping.")
            return
        }
        if (requireCharging && !isDeviceCharging(this)) {
            Log.d(TAG, "processAutoBackup: Require charging constraint enabled, but device is not plugged in. Skipping.")
            return
        }

        val uploadedSignatures = getUploadedSignatures(prefs)
        val candidates = mutableListOf<CandidateMedia>()

        val projection = mutableListOf(
            MediaStore.MediaColumns._ID,
            MediaStore.MediaColumns.DATA,
            MediaStore.MediaColumns.DISPLAY_NAME,
            MediaStore.MediaColumns.SIZE,
            MediaStore.MediaColumns.MIME_TYPE,
            MediaStore.MediaColumns.DATE_MODIFIED
        )
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            projection.add(MediaStore.MediaColumns.IS_PENDING)
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            projection.add(MediaStore.MediaColumns.IS_TRASHED)
        }

        val isoFormat = SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss.SSS'Z'", Locale.US).apply {
            timeZone = TimeZone.getTimeZone("UTC")
        }

        // Query both images and videos
        val urisToQuery = mutableListOf(MediaStore.Images.Media.EXTERNAL_CONTENT_URI)
        urisToQuery.add(MediaStore.Video.Media.EXTERNAL_CONTENT_URI)

        for (contentUri in urisToQuery) {
            val isVideoQuery = contentUri == MediaStore.Video.Media.EXTERNAL_CONTENT_URI
            val takenColName = if (isVideoQuery) MediaStore.Video.Media.DATE_TAKEN else MediaStore.Images.Media.DATE_TAKEN
            val proj = (projection + takenColName).toTypedArray()

            contentResolver.query(
                contentUri,
                proj,
                null,
                null,
                "${MediaStore.MediaColumns.DATE_MODIFIED} DESC"
            )?.use { cursor ->
                val dataCol = cursor.getColumnIndex(MediaStore.MediaColumns.DATA)
                val nameCol = cursor.getColumnIndex(MediaStore.MediaColumns.DISPLAY_NAME)
                val sizeCol = cursor.getColumnIndex(MediaStore.MediaColumns.SIZE)
                val mimeCol = cursor.getColumnIndex(MediaStore.MediaColumns.MIME_TYPE)
                val modCol = cursor.getColumnIndex(MediaStore.MediaColumns.DATE_MODIFIED)
                val takenCol = cursor.getColumnIndex(takenColName)
                val pendingCol = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                    cursor.getColumnIndex(MediaStore.MediaColumns.IS_PENDING)
                } else -1
                val trashedCol = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                    cursor.getColumnIndex(MediaStore.MediaColumns.IS_TRASHED)
                } else -1

                var count = 0
                while (cursor.moveToNext() && count < 50) {
                    count++
                    if (pendingCol != -1 && cursor.getInt(pendingCol) == 1) {
                        continue
                    }
                    if (trashedCol != -1 && cursor.getInt(trashedCol) == 1) {
                        continue
                    }

                    val path = if (dataCol != -1 && !cursor.isNull(dataCol)) cursor.getString(dataCol) else null
                    if (path.isNullOrEmpty()) continue
                    val file = File(path)
                    val size = if (sizeCol != -1 && !cursor.isNull(sizeCol)) cursor.getLong(sizeCol) else file.length()
                    if (!file.exists() || size <= 0) continue

                    val rawName = if (nameCol != -1 && !cursor.isNull(nameCol)) cursor.getString(nameCol) else null
                    val name = rawName ?: file.name
                    if (name.startsWith(".") || name.contains(".trashed") || name.contains(".pending") || file.name.startsWith(".")) {
                        continue
                    }
                    val rawMime = if (mimeCol != -1 && !cursor.isNull(mimeCol)) cursor.getString(mimeCol) else null
                    val mime = rawMime ?: (if (isVideoQuery) "video/mp4" else "image/jpeg")

                    // Check folder match
                    val folderId = classifyMediaFolder(path)
                    if (folderId == null || !config.enabledFolders.contains(folderId)) {
                        continue
                    }

                    // Check if already uploaded or ignored
                    if (isAlreadyBackedUpOrIgnored(name, size, uploadedSignatures)) {
                        continue
                    }

                    val dateTaken = if (takenCol != -1 && !cursor.isNull(takenCol)) cursor.getLong(takenCol) else 0L
                    val dateModified = if (modCol != -1 && !cursor.isNull(modCol)) cursor.getLong(modCol) * 1000L else 0L
                    val effectiveTime = if (dateTaken > 0) dateTaken else if (dateModified > 0) dateModified else file.lastModified()

                    // Only backup photos taken AFTER this folder's backup was started (skip past historical photos)
                    val folderStartTime = config.folderStartTimes[folderId] ?: config.backupStartTime
                    if (folderStartTime > 0L && effectiveTime < folderStartTime) {
                        Log.d(TAG, "Skipping $name: taken at $effectiveTime before folder '$folderId' start time $folderStartTime")
                        continue
                    }

                    val takenAtIso = isoFormat.format(Date(effectiveTime))

                    candidates.add(
                        CandidateMedia(
                            file = file,
                            filename = name,
                            mimeType = mime,
                            size = size,
                            takenAtIso = takenAtIso
                        )
                    )

                    // Limit batch to 15 per job run to avoid excessive background run time
                    if (candidates.size >= 15) break
                }
            }
        }

        if (candidates.isEmpty()) {
            Log.d(TAG, "processAutoBackup: No new candidate photos to upload.")
            return
        }

        Log.i(TAG, "processAutoBackup: Found ${candidates.size} new items to auto-backup.")

        try {
            for ((index, item) in candidates.withIndex()) {
                if (jobAborted.get()) break

                updateNotification(
                    title = "HomeSpace Auto-backup",
                    message = "Backing up ${index + 1}/${candidates.size}: ${item.filename}"
                )

                when (uploadFile(
                    serverUri = config.serverUri,
                    token = config.token,
                    file = item.file,
                    mimeType = item.mimeType,
                    takenAtIso = item.takenAtIso
                )) {
                    UploadOutcome.SUCCESS -> {
                        Log.i(TAG, "Successfully uploaded ${item.filename} in background!")
                        markItemUploaded(prefs, item.filename, item.size)
                        uploadedSignatures.uploaded.add("${item.filename.lowercase()}_${item.size}")
                    }
                    UploadOutcome.UNAUTHORIZED -> {
                        Log.w(TAG, "Auto-backup stopped: session expired or unauthorized (401).")
                        break
                    }
                    UploadOutcome.QUOTA_EXCEEDED -> {
                        Log.w(TAG, "Auto-backup paused: server storage quota exceeded (413).")
                        break
                    }
                    UploadOutcome.FAILED -> {
                        Log.w(TAG, "Failed to upload ${item.filename} in background.")
                    }
                }
            }
        } finally {
            cancelNotification()
        }
    }

    private enum class UploadOutcome { SUCCESS, UNAUTHORIZED, QUOTA_EXCEEDED, FAILED }

    private fun isPrivateOrLocalHttpHost(host: String): Boolean {
        val h = host.lowercase(Locale.US)
        if (h == "localhost" || h == "127.0.0.1" || h == "::1" || h == "10.0.2.2" ||
            h.endsWith(".local") || h.endsWith(".lan") || h.endsWith(".internal") || h.endsWith(".home.arpa")
        ) {
            return true
        }
        return try {
            val addr = InetAddress.getByName(h)
            if (addr.isLoopbackAddress || addr.isSiteLocalAddress || addr.isLinkLocalAddress) {
                return true
            }
            val bytes = addr.address
            if (bytes.size == 4) {
                val b0 = bytes[0].toInt() and 0xFF
                val b1 = bytes[1].toInt() and 0xFF
                // Tailscale CGNAT 100.64.0.0/10
                b0 == 100 && b1 in 64..127
            } else {
                false
            }
        } catch (_: Exception) {
            false
        }
    }

    private fun createPinnedSslSocketFactoryIfConfigured(hostPort: String): SSLSocketFactory? {
        val prefs = getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        val rawPins = prefs.getString(KEY_TRUSTED_CERT_PINS, null) ?: return null
        val expectedSha256 = try {
            JSONObject(rawPins).optString(hostPort, "")
        } catch (_: Exception) {
            ""
        }
        if (expectedSha256.isEmpty()) return null

        val tmf = javax.net.ssl.TrustManagerFactory.getInstance(
            javax.net.ssl.TrustManagerFactory.getDefaultAlgorithm()
        )
        tmf.init(null as java.security.KeyStore?)
        val defaultTm = tmf.trustManagers.filterIsInstance<X509TrustManager>().first()

        val trustManager = object : X509TrustManager {
            override fun checkClientTrusted(chain: Array<out X509Certificate>?, authType: String?) {
                defaultTm.checkClientTrusted(chain, authType)
            }
            override fun checkServerTrusted(chain: Array<out X509Certificate>?, authType: String?) {
                val leaf = chain?.firstOrNull()
                    ?: throw java.security.cert.CertificateException("Empty certificate chain")
                val digest = MessageDigest.getInstance("SHA-256").digest(leaf.encoded)
                val actualHex = digest.joinToString("") { "%02x".format(it) }
                if (!actualHex.equals(expectedSha256, ignoreCase = true)) {
                    throw java.security.cert.CertificateException("Certificate pin mismatch for $hostPort")
                }
            }
            override fun getAcceptedIssuers(): Array<X509Certificate> = defaultTm.acceptedIssuers
        }
        val sslContext = SSLContext.getInstance("TLS")
        sslContext.init(null, arrayOf<TrustManager>(trustManager), null)
        return sslContext.socketFactory
    }

    private fun uploadFile(
        serverUri: String,
        token: String,
        file: File,
        mimeType: String,
        takenAtIso: String
    ): UploadOutcome {
        val boundary = "==HomeSpaceBoundary${System.currentTimeMillis()}=="
        val lineEnd = "\r\n"
        val twoHyphens = "--"

        var conn: HttpURLConnection? = null
        try {
            val base = if (serverUri.endsWith("/")) serverUri else "$serverUri/"
            val encodedTakenAt = URLEncoder.encode(takenAtIso, "UTF-8")
            val url = URL("${base}api/media/upload?takenAt=$encodedTakenAt")
            if (url.protocol.equals("http", ignoreCase = true) && !isPrivateOrLocalHttpHost(url.host)) {
                Log.e(TAG, "Blocked insecure cleartext HTTP upload to non-local host: ${url.host}")
                return UploadOutcome.FAILED
            }
            conn = url.openConnection() as HttpURLConnection

            if (conn is HttpsURLConnection) {
                val port = if (url.port != -1) url.port else 443
                val pinnedFactory = createPinnedSslSocketFactoryIfConfigured("${url.host}:$port")
                if (pinnedFactory != null) {
                    conn.sslSocketFactory = pinnedFactory
                }
            }

            val safeFilename = file.name.replace("\"", "_").replace("\r", "").replace("\n", "")
            conn.requestMethod = "POST"
            conn.doInput = true
            conn.doOutput = true
            conn.useCaches = false
            conn.connectTimeout = 30000
            conn.readTimeout = 1800000 // 30 minutes for large videos
            conn.setRequestProperty("Connection", "Keep-Alive")
            conn.setRequestProperty("Authorization", "Bearer $token")
            conn.setRequestProperty("Content-Type", "multipart/form-data; boundary=$boundary")
            conn.setRequestProperty("x-taken-at", takenAtIso)

            val headerBytes = (
                "$twoHyphens$boundary$lineEnd" +
                "Content-Disposition: form-data; name=\"file\"; filename=\"$safeFilename\"$lineEnd" +
                "Content-Type: $mimeType$lineEnd$lineEnd"
            ).toByteArray(Charsets.UTF_8)

            val footerBytes = "$lineEnd$twoHyphens$boundary$twoHyphens$lineEnd".toByteArray(Charsets.UTF_8)
            val totalLength = headerBytes.size.toLong() +
                file.length() +
                footerBytes.size.toLong()

            conn.setFixedLengthStreamingMode(totalLength)

            conn.outputStream.use { os ->
                os.write(headerBytes)
                file.inputStream().use { input ->
                    val buffer = ByteArray(65536)
                    var bytesRead: Int
                    while (input.read(buffer).also { bytesRead = it } != -1) {
                        if (jobAborted.get()) {
                            return UploadOutcome.FAILED
                        }
                        os.write(buffer, 0, bytesRead)
                    }
                }
                os.write(footerBytes)
                os.flush()
            }

            return when (val responseCode = conn.responseCode) {
                in 200..299 -> UploadOutcome.SUCCESS
                401, 403 -> UploadOutcome.UNAUTHORIZED
                413 -> UploadOutcome.QUOTA_EXCEEDED
                else -> {
                    Log.w(TAG, "Upload returned HTTP $responseCode for ${file.name}")
                    UploadOutcome.FAILED
                }
            }
        } catch (e: Exception) {
            Log.e(TAG, "uploadFile failed for ${file.name}", e)
            return UploadOutcome.FAILED
        } finally {
            conn?.disconnect()
        }
    }

    private fun updateNotification(title: String, message: String) {
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU &&
                ContextCompat.checkSelfPermission(this, android.Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED
            ) {
                return
            }
            val notificationManager = getSystemService(Context.NOTIFICATION_SERVICE) as? NotificationManager ?: return

            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                val channel = NotificationChannel(
                    NOTIFICATION_CHANNEL_ID,
                    "HomeSpace Auto-backup",
                    NotificationManager.IMPORTANCE_LOW
                ).apply {
                    description = "Shows progress during background photo upload"
                }
                notificationManager.createNotificationChannel(channel)
            }

            val notification = NotificationCompat.Builder(this, NOTIFICATION_CHANNEL_ID)
                .setSmallIcon(android.R.drawable.stat_sys_upload)
                .setContentTitle(title)
                .setContentText(message)
                .setPriority(NotificationCompat.PRIORITY_LOW)
                .setOngoing(true)
                .build()

            notificationManager.notify(NOTIFICATION_ID, notification)
        } catch (_: Exception) {}
    }

    private fun cancelNotification() {
        try {
            val notificationManager = getSystemService(Context.NOTIFICATION_SERVICE) as? NotificationManager ?: return
            notificationManager.cancel(NOTIFICATION_ID)
        } catch (_: Exception) {}
    }
}
