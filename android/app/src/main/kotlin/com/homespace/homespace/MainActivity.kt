package com.homespace.homespace

import android.content.ContentValues
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.database.ContentObserver
import android.graphics.Bitmap
import android.media.MediaMetadataRetriever
import android.media.ThumbnailUtils
import android.os.Build
import android.os.Environment
import android.os.Handler
import android.os.Looper
import android.os.PowerManager
import android.provider.MediaStore
import android.util.Size
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileOutputStream
import java.util.concurrent.Executors

class MainActivity : FlutterActivity() {
    private val MEDIA_CHANNEL = "com.homespace.homespace/media_saver"
    private val PERMISSION_CHANNEL = "com.homespace.homespace/permissions"
    private val OBSERVER_CHANNEL = "com.homespace.homespace/media_observer"
    private val BACKUP_CHANNEL = "com.homespace.homespace/backup"
    private var permissionResult: MethodChannel.Result? = null
    private var mediaObserver: ContentObserver? = null
    private var eventSink: EventChannel.EventSink? = null
    private var uploadWakeLock: PowerManager.WakeLock? = null

    private fun acquireUploadWakeLock() {
        try {
            if (uploadWakeLock == null) {
                val powerManager = getSystemService(Context.POWER_SERVICE) as? PowerManager
                uploadWakeLock = powerManager?.newWakeLock(
                    PowerManager.PARTIAL_WAKE_LOCK,
                    "HomeSpace::UploadWakeLock"
                )
            }
            if (uploadWakeLock?.isHeld == false) {
                uploadWakeLock?.acquire(60 * 60 * 1000L) // 1 hour safety timeout
            }
        } catch (_: Throwable) {}
    }

    private fun releaseUploadWakeLock() {
        try {
            if (uploadWakeLock?.isHeld == true) {
                uploadWakeLock?.release()
            }
        } catch (_: Throwable) {}
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // 1. Media Saver Channel (Download to Gallery)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, MEDIA_CHANNEL).setMethodCallHandler { call, result ->
            if (call.method == "saveMedia") {
                val bytes = call.argument<ByteArray>("bytes")
                val fileName = call.argument<String>("fileName") ?: "media_${System.currentTimeMillis()}"
                val mimeType = call.argument<String>("mimeType") ?: "image/jpeg"

                if (bytes == null) {
                    result.error("INVALID_ARGS", "Bytes cannot be null", null)
                    return@setMethodCallHandler
                }

                try {
                    val isVideo = mimeType.startsWith("video/")
                    val collection = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                        if (isVideo) MediaStore.Video.Media.getContentUri(MediaStore.VOLUME_EXTERNAL_PRIMARY)
                        else MediaStore.Images.Media.getContentUri(MediaStore.VOLUME_EXTERNAL_PRIMARY)
                    } else {
                        if (isVideo) MediaStore.Video.Media.EXTERNAL_CONTENT_URI
                        else MediaStore.Images.Media.EXTERNAL_CONTENT_URI
                    }

                    val values = ContentValues().apply {
                        put(MediaStore.MediaColumns.DISPLAY_NAME, fileName)
                        put(MediaStore.MediaColumns.MIME_TYPE, mimeType)
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                            put(
                                MediaStore.MediaColumns.RELATIVE_PATH,
                                if (isVideo) Environment.DIRECTORY_MOVIES + "/HomeSpace" else Environment.DIRECTORY_PICTURES + "/HomeSpace"
                            )
                            put(MediaStore.MediaColumns.IS_PENDING, 1)
                        }
                    }

                    val uri = contentResolver.insert(collection, values)
                    if (uri != null) {
                        contentResolver.openOutputStream(uri)?.use { os ->
                            os.write(bytes)
                        }
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                            values.clear()
                            values.put(MediaStore.MediaColumns.IS_PENDING, 0)
                            contentResolver.update(uri, values, null, null)
                        }
                        result.success(uri.toString())
                    } else {
                        result.error("SAVE_FAILED", "Failed to create MediaStore entry", null)
                    }
                } catch (e: Exception) {
                    result.error("ERROR", e.localizedMessage, null)
                }
            } else if (call.method == "getVideoThumbnail") {
                val filePath = call.argument<String>("filePath")
                val fileName = call.argument<String>("fileName")
                val mainHandler = Handler(Looper.getMainLooper())

                Executors.newCachedThreadPool().execute {
                    try {
                        var resolvedFile: File? = if (!filePath.isNullOrEmpty()) File(filePath) else null
                        if (resolvedFile == null || !resolvedFile.exists()) {
                            // Try resolving by fileName via MediaStore
                            if (!fileName.isNullOrEmpty()) {
                                val proj = arrayOf(MediaStore.Video.Media.DATA)
                                contentResolver.query(
                                    MediaStore.Video.Media.EXTERNAL_CONTENT_URI,
                                    proj,
                                    "${MediaStore.Video.Media.DISPLAY_NAME} = ? COLLATE NOCASE",
                                    arrayOf(fileName),
                                    null
                                )?.use { cursor ->
                                    if (cursor.moveToFirst()) {
                                        val dataCol = cursor.getColumnIndex(MediaStore.Video.Media.DATA)
                                        if (dataCol != -1) {
                                            val p = cursor.getString(dataCol)
                                            if (!p.isNullOrEmpty() && File(p).exists()) {
                                                resolvedFile = File(p)
                                            }
                                        }
                                    }
                                }
                            }
                        }

                        if (resolvedFile == null || !resolvedFile.exists()) {
                            // Also check common camera directories if fileName provided
                            if (!fileName.isNullOrEmpty()) {
                                val candidateDirs = listOf(
                                    "/storage/emulated/0/DCIM/Camera",
                                    "/storage/emulated/0/DCIM",
                                    "/storage/emulated/0/Movies",
                                    "/storage/emulated/0/Movies/HomeSpace",
                                    "/storage/emulated/0/Download"
                                )
                                for (dir in candidateDirs) {
                                    val f = File(dir, fileName)
                                    if (f.exists() && f.length() > 0) {
                                        resolvedFile = f
                                        break
                                    }
                                }
                            }
                        }

                        if (resolvedFile == null || !resolvedFile.exists()) {
                            mainHandler.post { result.success(null) }
                            return@execute
                        }

                        val file = resolvedFile!!
                        val cacheKey = "${file.name}_${file.lastModified()}".hashCode().toString()
                        val thumbFile = File(cacheDir, "vid_thumb_$cacheKey.jpg")
                        if (thumbFile.exists() && thumbFile.length() > 0) {
                            mainHandler.post { result.success(thumbFile.absolutePath) }
                            return@execute
                        }

                        var bitmap: Bitmap? = null
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                            try {
                                bitmap = ThumbnailUtils.createVideoThumbnail(file, Size(512, 512), null)
                            } catch (_: Throwable) {}
                        }

                        if (bitmap == null) {
                            val retriever = MediaMetadataRetriever()
                            try {
                                retriever.setDataSource(file.absolutePath)
                                bitmap = retriever.getFrameAtTime(0, MediaMetadataRetriever.OPTION_CLOSEST_SYNC)
                                    ?: retriever.frameAtTime
                            } catch (_: Throwable) {
                            } finally {
                                try { retriever.release() } catch (_: Throwable) {}
                            }
                        }

                        if (bitmap != null) {
                            FileOutputStream(thumbFile).use { out ->
                                bitmap.compress(Bitmap.CompressFormat.JPEG, 85, out)
                            }
                            mainHandler.post { result.success(thumbFile.absolutePath) }
                        } else {
                            mainHandler.post { result.success(null) }
                        }
                    } catch (e: Throwable) {
                        mainHandler.post { result.success(null) }
                    }
                }
            } else if (call.method == "findLocalMedia") {
                val fileName = call.argument<String>("fileName")
                val isVideo = call.argument<Boolean>("isVideo") ?: false
                if (fileName.isNullOrEmpty()) {
                    result.success(null)
                    return@setMethodCallHandler
                }

                Executors.newCachedThreadPool().execute {
                    try {
                        val uri = if (isVideo) MediaStore.Video.Media.EXTERNAL_CONTENT_URI else MediaStore.Images.Media.EXTERNAL_CONTENT_URI
                        val proj = arrayOf(MediaStore.MediaColumns.DATA)
                        var foundPath: String? = null

                        contentResolver.query(
                            uri,
                            proj,
                            "${MediaStore.MediaColumns.DISPLAY_NAME} = ? COLLATE NOCASE",
                            arrayOf(fileName),
                            null
                        )?.use { cursor ->
                            if (cursor.moveToFirst()) {
                                val col = cursor.getColumnIndex(MediaStore.MediaColumns.DATA)
                                if (col != -1) {
                                    val p = cursor.getString(col)
                                    if (!p.isNullOrEmpty() && File(p).exists()) {
                                        foundPath = p
                                    }
                                }
                            }
                        }

                        if (foundPath == null) {
                            val candidateDirs = listOf(
                                "/storage/emulated/0/DCIM/Camera",
                                "/storage/emulated/0/DCIM",
                                "/storage/emulated/0/Pictures",
                                "/storage/emulated/0/Pictures/Screenshots",
                                "/storage/emulated/0/Pictures/HomeSpace",
                                "/storage/emulated/0/Movies",
                                "/storage/emulated/0/Movies/HomeSpace",
                                "/storage/emulated/0/Download",
                                "/storage/emulated/0/Android/media/com.whatsapp/WhatsApp/Media/WhatsApp Images",
                                "/storage/emulated/0/Android/media/com.whatsapp/WhatsApp/Media/WhatsApp Video"
                            )
                            for (dir in candidateDirs) {
                                val f = File(dir, fileName)
                                if (f.exists() && f.length() > 0) {
                                    foundPath = f.absolutePath
                                    break
                                }
                            }
                        }

                        Handler(Looper.getMainLooper()).post {
                            result.success(foundPath)
                        }
                    } catch (_: Throwable) {
                        Handler(Looper.getMainLooper()).post {
                            result.success(null)
                        }
                    }
                }
            } else if (call.method == "shareMedia") {
                val filePath = call.argument<String>("filePath")
                val mimeType = call.argument<String>("mimeType") ?: "*/*"
                if (!filePath.isNullOrEmpty()) {
                    val file = File(filePath)
                    if (file.exists()) {
                        try {
                            val uri = FileProvider.getUriForFile(
                                this,
                                "${applicationContext.packageName}.fileprovider",
                                file
                            )
                            val shareIntent = Intent(Intent.ACTION_SEND).apply {
                                type = mimeType
                                putExtra(Intent.EXTRA_STREAM, uri)
                                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                            }
                            startActivity(Intent.createChooser(shareIntent, "Share memory via"))
                            result.success(true)
                        } catch (e: Exception) {
                            result.error("SHARE_ERROR", e.localizedMessage, null)
                        }
                    } else {
                        result.error("NOT_FOUND", "File does not exist: $filePath", null)
                    }
                } else {
                    result.error("INVALID_ARGS", "filePath is required", null)
                }
            } else if (call.method == "acquireWakeLock") {
                acquireUploadWakeLock()
                result.success(true)
            } else if (call.method == "releaseWakeLock") {
                releaseUploadWakeLock()
                result.success(true)
            } else {
                result.notImplemented()
            }
        }

        // 2. Permission Channel (For Auto Backup)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, PERMISSION_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "checkStoragePermission" -> {
                    result.success(checkStoragePermission())
                }
                "requestStoragePermission" -> {
                    if (checkStoragePermission()) {
                        result.success(true)
                    } else {
                        permissionResult = result
                        val perms = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                            arrayOf(
                                android.Manifest.permission.READ_MEDIA_IMAGES,
                                android.Manifest.permission.READ_MEDIA_VIDEO
                            )
                        } else {
                            arrayOf(android.Manifest.permission.READ_EXTERNAL_STORAGE)
                        }
                        ActivityCompat.requestPermissions(this, perms, 1001)
                    }
                }
                "queryCameraMedia" -> {
                    try {
                        val mediaList = queryDeviceMedia()
                        result.success(mediaList)
                    } catch (e: Exception) {
                        result.error("QUERY_FAILED", e.localizedMessage, null)
                    }
                }
                else -> result.notImplemented()
            }
        }

        // 3. Media Observer Channel (Real-time auto backup on camera capture)
        EventChannel(flutterEngine.dartExecutor.binaryMessenger, OBSERVER_CHANNEL).setStreamHandler(
            object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    eventSink = events
                    registerMediaObserver()
                }

                override fun onCancel(arguments: Any?) {
                    unregisterMediaObserver()
                    eventSink = null
                }
            }
        )

        // 4. Background Auto Backup Sync Channel
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, BACKUP_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "syncBackupConfig" -> {
                    val serverUri = call.argument<String>("serverUri")
                    val token = call.argument<String>("token")
                    val enabledFolders = call.argument<List<String>>("enabledFolders")
                    val backupStartTime = (call.argument<Number>("backupStartTime"))?.toLong()
                    val folderStartTimes = call.argument<Map<String, Number>>("folderStartTimes")

                    val prefs = getSharedPreferences(AutoBackupJobService.PREFS_NAME, Context.MODE_PRIVATE)
                    val editor = prefs.edit()
                    if (!serverUri.isNullOrEmpty()) {
                        editor.putString(AutoBackupJobService.KEY_SERVER_URI, serverUri)
                    }
                    if (!token.isNullOrEmpty()) {
                        editor.putString(AutoBackupJobService.KEY_AUTH_TOKEN, token)
                    }
                    if (enabledFolders != null) {
                        editor.putStringSet(AutoBackupJobService.KEY_ENABLED_FOLDERS, enabledFolders.toSet())
                    }
                    if (backupStartTime != null && backupStartTime > 0L) {
                        editor.putLong(AutoBackupJobService.KEY_BACKUP_START_TIME, backupStartTime)
                    }
                    if (folderStartTimes != null) {
                        val obj = org.json.JSONObject()
                        for ((key, value) in folderStartTimes) {
                            obj.put(key, value.toLong())
                        }
                        editor.putString(AutoBackupJobService.KEY_FOLDER_START_TIMES, obj.toString())
                    }
                    editor.apply()

                    AutoBackupJobService.schedule(this)
                    result.success(true)
                }
                "scheduleBackgroundBackup" -> {
                    AutoBackupJobService.schedule(this)
                    result.success(true)
                }
                "isBackgroundBackupScheduled" -> {
                    result.success(AutoBackupJobService.isScheduled(this))
                }
                "markMediaDeleted" -> {
                    val filenames = call.argument<List<String>>("filenames") ?: emptyList()
                    AutoBackupJobService.markMediaIgnoredOrDeleted(this, filenames)
                    result.success(true)
                }
                "unmarkMediaDeleted" -> {
                    val filenames = call.argument<List<String>>("filenames") ?: emptyList()
                    AutoBackupJobService.unmarkMediaIgnoredOrDeleted(this, filenames)
                    result.success(true)
                }
                "markItemUploaded" -> {
                    val filename = call.argument<String>("filename")
                    val size = (call.argument<Number>("size"))?.toLong() ?: 0L
                    if (!filename.isNullOrEmpty()) {
                        AutoBackupJobService.markItemUploaded(this, filename, size)
                    }
                    result.success(true)
                }
                "getIgnoredOrDeletedItems" -> {
                    result.success(AutoBackupJobService.getIgnoredOrDeletedItems(this))
                }
                else -> result.notImplemented()
            }
        }

        // Ensure background AutoBackupJobService is armed on app start
        try {
            AutoBackupJobService.schedule(this)
        } catch (_: Exception) {}
    }

    private fun registerMediaObserver() {
        if (mediaObserver != null) return
        mediaObserver = object : ContentObserver(Handler(Looper.getMainLooper())) {
            override fun onChange(selfChange: Boolean) {
                super.onChange(selfChange)
                eventSink?.success("media_changed")
            }
        }
        try {
            contentResolver.registerContentObserver(
                MediaStore.Images.Media.EXTERNAL_CONTENT_URI,
                true,
                mediaObserver!!
            )
            contentResolver.registerContentObserver(
                MediaStore.Video.Media.EXTERNAL_CONTENT_URI,
                true,
                mediaObserver!!
            )
        } catch (_: Exception) {}
    }

    private fun unregisterMediaObserver() {
        mediaObserver?.let {
            try {
                contentResolver.unregisterContentObserver(it)
            } catch (_: Exception) {}
            mediaObserver = null
        }
    }

    override fun onDestroy() {
        releaseUploadWakeLock()
        unregisterMediaObserver()
        super.onDestroy()
    }

    private fun checkStoragePermission(): Boolean {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            ContextCompat.checkSelfPermission(this, android.Manifest.permission.READ_MEDIA_IMAGES) == PackageManager.PERMISSION_GRANTED ||
            ContextCompat.checkSelfPermission(this, android.Manifest.permission.READ_MEDIA_VIDEO) == PackageManager.PERMISSION_GRANTED
        } else {
            ContextCompat.checkSelfPermission(this, android.Manifest.permission.READ_EXTERNAL_STORAGE) == PackageManager.PERMISSION_GRANTED
        }
    }

    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == 1001) {
            val granted = grantResults.isNotEmpty() && grantResults.any { it == PackageManager.PERMISSION_GRANTED }
            permissionResult?.success(granted)
            permissionResult = null
        }
    }

    private fun queryDeviceMedia(): List<Map<String, Any>> {
        val result = mutableListOf<Map<String, Any>>()
        val projectionList = mutableListOf(
            MediaStore.MediaColumns._ID,
            MediaStore.MediaColumns.DATA,
            MediaStore.MediaColumns.DISPLAY_NAME,
            MediaStore.MediaColumns.SIZE,
            MediaStore.MediaColumns.MIME_TYPE,
            MediaStore.MediaColumns.DATE_MODIFIED
        )
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            projectionList.add(MediaStore.MediaColumns.IS_PENDING)
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            projectionList.add(MediaStore.MediaColumns.IS_TRASHED)
        }

        // Query Images
        val imageUri = MediaStore.Images.Media.EXTERNAL_CONTENT_URI
        val imgProj = (projectionList + MediaStore.Images.Media.DATE_TAKEN).toTypedArray()
        contentResolver.query(imageUri, imgProj, null, null, "${MediaStore.MediaColumns.DATE_MODIFIED} DESC")?.use { cursor ->
            val dataCol = cursor.getColumnIndexOrThrow(MediaStore.MediaColumns.DATA)
            val nameCol = cursor.getColumnIndexOrThrow(MediaStore.MediaColumns.DISPLAY_NAME)
            val sizeCol = cursor.getColumnIndexOrThrow(MediaStore.MediaColumns.SIZE)
            val mimeCol = cursor.getColumnIndexOrThrow(MediaStore.MediaColumns.MIME_TYPE)
            val modCol = cursor.getColumnIndexOrThrow(MediaStore.MediaColumns.DATE_MODIFIED)
            val takenCol = cursor.getColumnIndex(MediaStore.Images.Media.DATE_TAKEN)
            val pendingCol = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) cursor.getColumnIndex(MediaStore.MediaColumns.IS_PENDING) else -1
            val trashedCol = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) cursor.getColumnIndex(MediaStore.MediaColumns.IS_TRASHED) else -1

            while (cursor.moveToNext() && result.size < 200) {
                if (pendingCol != -1 && cursor.getInt(pendingCol) == 1) continue
                if (trashedCol != -1 && cursor.getInt(trashedCol) == 1) continue

                val path = cursor.getString(dataCol) ?: continue
                val name = cursor.getString(nameCol) ?: File(path).name
                if (name.startsWith(".") || name.contains(".trashed") || name.contains(".pending") || File(path).name.startsWith(".")) {
                    continue
                }

                val size = cursor.getLong(sizeCol)
                val mime = cursor.getString(mimeCol) ?: "image/jpeg"
                val dateTaken = if (takenCol != -1) cursor.getLong(takenCol) else 0L
                val dateModified = cursor.getLong(modCol) * 1000L
                val effectiveTime = if (dateTaken > 0) dateTaken else if (dateModified > 0) dateModified else File(path).lastModified()

                if (File(path).exists() && size > 0) {
                    result.add(mapOf(
                        "path" to path,
                        "name" to name,
                        "size" to size,
                        "mimeType" to mime,
                        "isVideo" to false,
                        "dateTaken" to effectiveTime
                    ))
                }
            }
        }

        // Query Videos
        val videoUri = MediaStore.Video.Media.EXTERNAL_CONTENT_URI
        val vidProj = (projectionList + MediaStore.Video.Media.DATE_TAKEN).toTypedArray()
        contentResolver.query(videoUri, vidProj, null, null, "${MediaStore.MediaColumns.DATE_MODIFIED} DESC")?.use { cursor ->
            val dataCol = cursor.getColumnIndexOrThrow(MediaStore.MediaColumns.DATA)
            val nameCol = cursor.getColumnIndexOrThrow(MediaStore.MediaColumns.DISPLAY_NAME)
            val sizeCol = cursor.getColumnIndexOrThrow(MediaStore.MediaColumns.SIZE)
            val mimeCol = cursor.getColumnIndexOrThrow(MediaStore.MediaColumns.MIME_TYPE)
            val modCol = cursor.getColumnIndexOrThrow(MediaStore.MediaColumns.DATE_MODIFIED)
            val takenCol = cursor.getColumnIndex(MediaStore.Video.Media.DATE_TAKEN)
            val pendingCol = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) cursor.getColumnIndex(MediaStore.MediaColumns.IS_PENDING) else -1
            val trashedCol = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) cursor.getColumnIndex(MediaStore.MediaColumns.IS_TRASHED) else -1

            while (cursor.moveToNext() && result.size < 300) {
                if (pendingCol != -1 && cursor.getInt(pendingCol) == 1) continue
                if (trashedCol != -1 && cursor.getInt(trashedCol) == 1) continue

                val path = cursor.getString(dataCol) ?: continue
                val name = cursor.getString(nameCol) ?: File(path).name
                if (name.startsWith(".") || name.contains(".trashed") || name.contains(".pending") || File(path).name.startsWith(".")) {
                    continue
                }

                val size = cursor.getLong(sizeCol)
                val mime = cursor.getString(mimeCol) ?: "video/mp4"
                val dateTaken = if (takenCol != -1) cursor.getLong(takenCol) else 0L
                val dateModified = cursor.getLong(modCol) * 1000L
                val effectiveTime = if (dateTaken > 0) dateTaken else if (dateModified > 0) dateModified else File(path).lastModified()

                if (File(path).exists() && size > 0) {
                    result.add(mapOf(
                        "path" to path,
                        "name" to name,
                        "size" to size,
                        "mimeType" to mime,
                        "isVideo" to true,
                        "dateTaken" to effectiveTime
                    ))
                }
            }
        }

        return result
    }
}
