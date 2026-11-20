package com.homespace.homespace

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.job.JobInfo
import android.app.job.JobParameters
import android.app.job.JobScheduler
import android.app.job.JobService
import android.content.ComponentName
import android.content.Context
import android.content.SharedPreferences
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.provider.MediaStore
import android.util.Log
import androidx.core.app.NotificationCompat
import androidx.core.content.ContextCompat
import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import java.net.HttpURLConnection
import java.net.URL
import java.security.SecureRandom
import java.security.cert.X509Certificate
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.TimeZone
import java.util.concurrent.Executors
import javax.net.ssl.HostnameVerifier
import javax.net.ssl.HttpsURLConnection
import javax.net.ssl.SSLContext
import javax.net.ssl.SSLSocketFactory
import javax.net.ssl.TrustManager
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

        private const val NOTIFICATION_CHANNEL_ID = "homespace_auto_backup"
        private const val NOTIFICATION_ID = 9003

        private val executor = Executors.newSingleThreadExecutor()

        fun markItemUploaded(context: Context, filename: String, size: Long = 0L) {
            val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            val current = prefs.getStringSet(KEY_UPLOADED_ITEMS, null)?.toMutableSet() ?: mutableSetOf()
            current.add(filename.lowercase())
            if (size > 0L) {
                current.add("${filename.lowercase()}_$size")
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

        /**
         * Schedules both the real-time ContentUri trigger job (for instant camera capture detection)
         * and the 15-minute periodic fallback job.
         */
        fun schedule(context: Context) {
            val jobScheduler = context.getSystemService(Context.JOB_SCHEDULER_SERVICE) as? JobScheduler ?: return
            val component = ComponentName(context, AutoBackupJobService::class.java)

            // 1. Content URI trigger job (wakes up when Camera app captures a photo or video)
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
                    .setTriggerContentUpdateDelay(1500) // 1.5s delay so camera app finishes writing file
                    .setTriggerContentMaxDelay(4000)   // 4s max delay
                    .setRequiredNetworkType(JobInfo.NETWORK_TYPE_ANY)

                val result = jobScheduler.schedule(triggerBuilder.build())
                Log.d(TAG, "Scheduled ContentUri trigger job (id=$CONTENT_TRIGGER_JOB_ID, result=$result)")
            } catch (e: Exception) {
                Log.e(TAG, "Failed to schedule ContentUri trigger job", e)
            }

            // 2. Periodic fallback job (runs every 15 minutes as safety net)
            try {
                val periodicBuilder = JobInfo.Builder(PERIODIC_BACKUP_JOB_ID, component)
                    .setPeriodic(15 * 60 * 1000)
                    .setRequiredNetworkType(JobInfo.NETWORK_TYPE_ANY)
                    .setPersisted(true)

                val result = jobScheduler.schedule(periodicBuilder.build())
                Log.d(TAG, "Scheduled periodic backup job (id=$PERIODIC_BACKUP_JOB_ID, result=$result)")
            } catch (_: Exception) {
                // If setPersisted is denied by device/permissions, schedule non-persisted periodic
                try {
                    val periodicBuilder = JobInfo.Builder(PERIODIC_BACKUP_JOB_ID, component)
                        .setPeriodic(15 * 60 * 1000)
                        .setRequiredNetworkType(JobInfo.NETWORK_TYPE_ANY)
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

    override fun onStartJob(params: JobParameters?): Boolean {
        Log.d(TAG, "onStartJob triggered with id=${params?.jobId}")

        // Re-arm the trigger immediately so any subsequent photo taken will also trigger
        if (params?.jobId == CONTENT_TRIGGER_JOB_ID) {
            schedule(applicationContext)
        }

        executor.execute {
            try {
                processAutoBackup(params)
            } catch (e: Exception) {
                Log.e(TAG, "Error in background auto backup processing", e)
            } finally {
                if (params != null) {
                    jobFinished(params, false)
                }
            }
        }

        return true // Work is running asynchronously
    }

    override fun onStopJob(params: JobParameters?): Boolean {
        Log.d(TAG, "onStopJob called for id=${params?.jobId}")
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

        // Fallback 1: check app_flutter/homespace/session.json
        if (serverUri.isNullOrEmpty() || token.isNullOrEmpty()) {
            try {
                val dataDir = applicationInfo.dataDir
                val sessionFile = File(dataDir, "app_flutter/homespace/session.json")
                if (sessionFile.exists()) {
                    val json = JSONObject(sessionFile.readText())
                    if (token.isNullOrEmpty()) token = json.optString("token", null)
                    if (serverUri.isNullOrEmpty()) serverUri = json.optString("serverUri", null)
                }
            } catch (_: Exception) {}
        }

        // Fallback 2: default server URI if still null
        if (serverUri.isNullOrEmpty()) {
            serverUri = "https://vishal-hp-laptop-15s-fr5xxx.tailda4c64.ts.net:8443"
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
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            ContextCompat.checkSelfPermission(this, android.Manifest.permission.READ_MEDIA_IMAGES) == PackageManager.PERMISSION_GRANTED ||
            ContextCompat.checkSelfPermission(this, android.Manifest.permission.READ_MEDIA_VIDEO) == PackageManager.PERMISSION_GRANTED
        } else {
            ContextCompat.checkSelfPermission(this, android.Manifest.permission.READ_EXTERNAL_STORAGE) == PackageManager.PERMISSION_GRANTED
        }
    }

    private fun getUploadedSignatures(prefs: SharedPreferences): MutableSet<String> {
        val set = prefs.getStringSet(KEY_UPLOADED_ITEMS, null)?.toMutableSet() ?: mutableSetOf()

        // Include any ignored or deleted items
        val ignored = prefs.getStringSet(KEY_IGNORED_OR_DELETED_ITEMS, null)
        if (ignored != null) {
            for (item in ignored) {
                set.add(item.lowercase())
            }
        }

        // Also check deleted_signatures.json
        try {
            val dataDir = applicationInfo.dataDir
            val delFile = File(dataDir, "app_flutter/homespace/deleted_signatures.json")
            if (delFile.exists()) {
                val arr = org.json.JSONArray(delFile.readText())
                for (i in 0 until arr.length()) {
                    val s = arr.optString(i, "")
                    if (s.isNotEmpty()) {
                        set.add(s.lowercase())
                    }
                }
            }
        } catch (_: Exception) {}

        // Also cross-reference with library.json to include anything already synced (both active and trashed)
        try {
            val dataDir = applicationInfo.dataDir
            val libFile = File(dataDir, "app_flutter/homespace/library.json")
            if (libFile.exists()) {
                val json = JSONObject(libFile.readText())
                val media = json.optJSONArray("media") ?: json.optJSONArray("items")
                if (media != null) {
                    for (i in 0 until media.length()) {
                        val it = media.getJSONObject(i)
                        val title = it.optString("title", "")
                        if (title.isNotEmpty()) {
                            set.add(title.lowercase())
                        }
                    }
                }
            }
        } catch (_: Exception) {}

        return set
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
                        // File is still being written by camera app, skip for now
                        continue
                    }
                    if (trashedCol != -1 && cursor.getInt(trashedCol) == 1) {
                        // File is in OS trash, skip
                        continue
                    }

                    val path = if (dataCol != -1) cursor.getString(dataCol) else null ?: continue
                    val file = File(path)
                    val size = if (sizeCol != -1) cursor.getLong(sizeCol) else file.length()
                    if (!file.exists() || size <= 0) continue

                    val name = if (nameCol != -1) cursor.getString(nameCol) ?: file.name else file.name
                    if (name.startsWith(".") || name.contains(".trashed") || name.contains(".pending") || file.name.startsWith(".")) {
                        continue
                    }
                    val mime = if (mimeCol != -1) cursor.getString(mimeCol) ?: (if (isVideoQuery) "video/mp4" else "image/jpeg") else "image/jpeg"

                    // Check folder match
                    val folderId = classifyMediaFolder(path)
                    if (folderId == null || !config.enabledFolders.contains(folderId)) {
                        continue
                    }

                    // Check if already uploaded
                    if (uploadedSignatures.contains(name.lowercase()) ||
                        uploadedSignatures.contains("${name.lowercase()}_$size")) {
                        continue
                    }

                    val dateTaken = if (takenCol != -1) cursor.getLong(takenCol) else 0L
                    val dateModified = if (modCol != -1) cursor.getLong(modCol) * 1000L else 0L
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

        Log.i(TAG, "processAutoBackup: Found ${candidates.size} new items to auto-backup to ${config.serverUri}.")

        // Upload candidates one by one
        for ((index, item) in candidates.withIndex()) {
            updateNotification(
                title = "HomeSpace Auto-backup",
                message = "Backing up ${index + 1}/${candidates.size}: ${item.filename}"
            )

            val success = uploadFile(
                serverUri = config.serverUri,
                token = config.token,
                file = item.file,
                mimeType = item.mimeType,
                takenAtIso = item.takenAtIso
            )

            if (success) {
                Log.i(TAG, "Successfully uploaded ${item.filename} in background!")
                markItemUploaded(prefs, item.filename, item.size)
                uploadedSignatures.add(item.filename.lowercase())
                uploadedSignatures.add("${item.filename.lowercase()}_${item.size}")
            } else {
                Log.w(TAG, "Failed to upload ${item.filename} in background.")
            }
        }

        cancelNotification()
    }

    private fun extractVideoThumbnail(file: File): File? {
        try {
            val thumbFile = File(cacheDir, "vid_thumb_${file.name.hashCode()}.jpg")
            if (thumbFile.exists() && thumbFile.length() > 0) return thumbFile

            var bitmap: android.graphics.Bitmap? = null
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                try {
                    bitmap = android.media.ThumbnailUtils.createVideoThumbnail(file, android.util.Size(512, 512), null)
                } catch (_: Throwable) {}
            }
            if (bitmap == null) {
                val retriever = android.media.MediaMetadataRetriever()
                try {
                    retriever.setDataSource(file.absolutePath)
                    bitmap = retriever.getFrameAtTime(1000000, android.media.MediaMetadataRetriever.OPTION_CLOSEST_SYNC)
                        ?: retriever.frameAtTime
                } catch (_: Throwable) {
                } finally {
                    try { retriever.release() } catch (_: Throwable) {}
                }
            }
            if (bitmap != null) {
                java.io.FileOutputStream(thumbFile).use { out ->
                    bitmap.compress(android.graphics.Bitmap.CompressFormat.JPEG, 85, out)
                }
                return thumbFile
            }
        } catch (_: Throwable) {}
        return null
    }

    private fun uploadFile(
        serverUri: String,
        token: String,
        file: File,
        mimeType: String,
        takenAtIso: String
    ): Boolean {
        val boundary = "==HomeSpaceBoundary${System.currentTimeMillis()}=="
        val lineEnd = "\r\n"
        val twoHyphens = "--"

        var conn: HttpURLConnection? = null
        try {
            val base = if (serverUri.endsWith("/")) serverUri else "$serverUri/"
            val url = URL("${base}api/media/upload?takenAt=$takenAtIso")
            conn = url.openConnection() as HttpURLConnection

            if (conn is HttpsURLConnection) {
                conn.sslSocketFactory = createTrustAllSslSocketFactory()
                conn.hostnameVerifier = HostnameVerifier { _, _ -> true }
            }

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
                "Content-Disposition: form-data; name=\"file\"; filename=\"${file.name}\"$lineEnd" +
                "Content-Type: $mimeType$lineEnd$lineEnd"
            ).toByteArray(Charsets.UTF_8)

            val footerBytes = "$lineEnd$twoHyphens$boundary$twoHyphens$lineEnd".toByteArray(Charsets.UTF_8)
            val totalLength = headerBytes.size.toLong() +
                file.length() +
                footerBytes.size.toLong()

            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.KITKAT) {
                conn.setFixedLengthStreamingMode(totalLength)
            } else {
                conn.setChunkedStreamingMode(65536)
            }

            conn.outputStream.use { os ->
                os.write(headerBytes)
                file.inputStream().use { input ->
                    val buffer = ByteArray(65536)
                    var bytesRead: Int
                    while (input.read(buffer).also { bytesRead = it } != -1) {
                        os.write(buffer, 0, bytesRead)
                    }
                }
                os.write(footerBytes)
                os.flush()
            }

            val responseCode = conn.responseCode
            return responseCode in 200..299
        } catch (e: Exception) {
            Log.e(TAG, "uploadFile failed for ${file.name}", e)
            return false
        } finally {
            conn?.disconnect()
        }
    }

    private fun createTrustAllSslSocketFactory(): SSLSocketFactory {
        val trustAllCerts = arrayOf<TrustManager>(object : X509TrustManager {
            override fun checkClientTrusted(chain: Array<out X509Certificate>?, authType: String?) {}
            override fun checkServerTrusted(chain: Array<out X509Certificate>?, authType: String?) {}
            override fun getAcceptedIssuers(): Array<X509Certificate> = arrayOf()
        })
        val sslContext = SSLContext.getInstance("TLS")
        sslContext.init(null, trustAllCerts, SecureRandom())
        return sslContext.socketFactory
    }

    private fun updateNotification(title: String, message: String) {
        try {
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
