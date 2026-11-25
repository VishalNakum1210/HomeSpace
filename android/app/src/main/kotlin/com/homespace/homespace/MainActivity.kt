package com.homespace.homespace

import android.app.Activity
import android.app.RecoverableSecurityException
import android.content.ContentUris
import android.content.ContentValues
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.database.ContentObserver
import android.graphics.Bitmap
import android.media.MediaMetadataRetriever
import android.media.ThumbnailUtils
import android.net.Uri
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
import java.security.MessageDigest
import java.util.concurrent.Executors

class MainActivity : FlutterActivity() {
    private val MEDIA_CHANNEL = "com.homespace.homespace/media_saver"
    private val PERMISSION_CHANNEL = "com.homespace.homespace/permissions"
    private val OBSERVER_CHANNEL = "com.homespace.homespace/media_observer"
    private val BACKUP_CHANNEL = "com.homespace.homespace/backup"

    companion object {
        private const val REQUEST_CODE_MEDIA_PERMISSION = 1001
        private const val REQUEST_CODE_DELETE_MEDIA = 1002
    }

    private val ioExecutor = Executors.newFixedThreadPool(4)
    private val mainHandler = Handler(Looper.getMainLooper())
    private var permissionResult: MethodChannel.Result? = null
    private var pendingDeleteResult: MethodChannel.Result? = null
    private var mediaObserver: ContentObserver? = null
    private var eventSink: EventChannel.EventSink? = null
    private var uploadWakeLock: PowerManager.WakeLock? = null

    private fun sha256Hex(value: String): String {
        val bytes = MessageDigest.getInstance("SHA-256").digest(value.toByteArray(Charsets.UTF_8))
        return bytes.joinToString("") { "%02x".format(it) }.take(32)
    }

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
                val filePath = call.argument<String>("filePath")
                val bytes = call.argument<ByteArray>("bytes")
                val fileName = call.argument<String>("fileName") ?: "media_${System.currentTimeMillis()}"
                val mimeType = call.argument<String>("mimeType") ?: "image/jpeg"

                if (filePath.isNullOrEmpty() && bytes == null) {
                    result.error("INVALID_ARGS", "Either filePath or bytes must be provided", null)
                    return@setMethodCallHandler
                }

                ioExecutor.execute {
                    var insertedUri: Uri? = null
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
                        if (uri == null) {
                            mainHandler.post { result.error("SAVE_FAILED", "Failed to create MediaStore entry", null) }
                            return@execute
                        }
                        insertedUri = uri

                        val os = contentResolver.openOutputStream(uri)
                            ?: throw IllegalStateException("Unable to open MediaStore output stream")
                        os.use { out ->
                            if (!filePath.isNullOrEmpty()) {
                                File(filePath).inputStream().use { input ->
                                    input.copyTo(out, bufferSize = 64 * 1024)
                                }
                            } else if (bytes != null) {
                                out.write(bytes)
                            }
                        }
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                            values.clear()
                            values.put(MediaStore.MediaColumns.IS_PENDING, 0)
                            contentResolver.update(uri, values, null, null)
                        }
                        mainHandler.post { result.success(uri.toString()) }
                    } catch (e: Exception) {
                        if (insertedUri != null) {
                            try { contentResolver.delete(insertedUri!!, null, null) } catch (_: Exception) {}
                        }
                        mainHandler.post { result.error("ERROR", e.localizedMessage ?: "Failed to save media", null) }
                    }
                }
            } else if (call.method == "getVideoThumbnail") {
                val filePath = call.argument<String>("filePath")
                val fileName = call.argument<String>("fileName")

                ioExecutor.execute {
                    try {
                        // Check if we have an existing persistent thumbnail cached by fileName
                        if (!fileName.isNullOrEmpty()) {
                            val nameHash = sha256Hex(fileName.lowercase())
                            val nameThumbFile = File(cacheDir, "vid_thumb_name_$nameHash.jpg")
                            if (nameThumbFile.exists() && nameThumbFile.length() > 0) {
                                mainHandler.post { result.success(nameThumbFile.absolutePath) }
                                return@execute
                            }
                        }

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
                                        if (dataCol != -1 && !cursor.isNull(dataCol)) {
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
                        val cacheKey = sha256Hex("${file.absolutePath}_${file.lastModified()}_${file.length()}")
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
                            try {
                                val nameHash = sha256Hex(file.name.lowercase())
                                val nameThumbFile = File(cacheDir, "vid_thumb_name_$nameHash.jpg")
                                FileOutputStream(nameThumbFile).use { out ->
                                    bitmap.compress(Bitmap.CompressFormat.JPEG, 85, out)
                                }
                            } catch (_: Throwable) {}
                            mainHandler.post { result.success(thumbFile.absolutePath) }
                        } else {
                            mainHandler.post { result.success(null) }
                        }
                    } catch (_: Throwable) {
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

                ioExecutor.execute {
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
                                if (col != -1 && !cursor.isNull(col)) {
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

                        mainHandler.post {
                            result.success(foundPath)
                        }
                    } catch (_: Throwable) {
                        mainHandler.post {
                            result.success(null)
                        }
                    }
                }
            } else if (call.method == "deleteDeviceFile") {
                val filePath = call.argument<String>("filePath")
                if (filePath.isNullOrEmpty()) {
                    result.success(false)
                    return@setMethodCallHandler
                }
                ioExecutor.execute {
                    deleteDeviceMediaFile(filePath, result)
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
            } else if (call.method == "shareMultipleMedia") {
                val filePaths = call.argument<List<String>>("filePaths") ?: emptyList()
                val mimeType = call.argument<String>("mimeType") ?: "*/*"
                if (filePaths.isEmpty()) {
                    result.error("INVALID_ARGS", "filePaths is required", null)
                    return@setMethodCallHandler
                }
                try {
                    val uris = ArrayList<Uri>()
                    for (fp in filePaths) {
                        val file = File(fp)
                        if (file.exists()) {
                            uris.add(
                                FileProvider.getUriForFile(
                                    this,
                                    "${applicationContext.packageName}.fileprovider",
                                    file
                                )
                            )
                        }
                    }
                    if (uris.isEmpty()) {
                        result.error("NOT_FOUND", "None of the files exist on device", null)
                        return@setMethodCallHandler
                    }
                    val intent = if (uris.size == 1) {
                        Intent(Intent.ACTION_SEND).apply {
                            type = mimeType
                            putExtra(Intent.EXTRA_STREAM, uris[0])
                            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                        }
                    } else {
                        Intent(Intent.ACTION_SEND_MULTIPLE).apply {
                            type = mimeType
                            putParcelableArrayListExtra(Intent.EXTRA_STREAM, uris)
                            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                        }
                    }
                    startActivity(Intent.createChooser(intent, "Share ${uris.size} memories via"))
                    result.success(true)
                } catch (e: Exception) {
                    result.error("SHARE_ERROR", e.localizedMessage, null)
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
                    } else if (permissionResult != null) {
                        result.error("IN_PROGRESS", "A permission request is already active.", null)
                    } else {
                        permissionResult = result
                        val perms = if (Build.VERSION.SDK_INT >= 34) {
                            arrayOf(
                                android.Manifest.permission.READ_MEDIA_IMAGES,
                                android.Manifest.permission.READ_MEDIA_VIDEO,
                                android.Manifest.permission.READ_MEDIA_VISUAL_USER_SELECTED
                            )
                        } else if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                            arrayOf(
                                android.Manifest.permission.READ_MEDIA_IMAGES,
                                android.Manifest.permission.READ_MEDIA_VIDEO
                            )
                        } else {
                            arrayOf(android.Manifest.permission.READ_EXTERNAL_STORAGE)
                        }
                        ActivityCompat.requestPermissions(this, perms, REQUEST_CODE_MEDIA_PERMISSION)
                    }
                }
                "queryCameraMedia" -> {
                    ioExecutor.execute {
                        try {
                            val mediaList = queryDeviceMedia()
                            mainHandler.post { result.success(mediaList) }
                        } catch (e: Exception) {
                            mainHandler.post { result.error("QUERY_FAILED", e.localizedMessage, null) }
                        }
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
                    val wifiOnly = call.argument<Boolean>("wifiOnly")
                    val requireCharging = call.argument<Boolean>("requireCharging")
                    val pinnedCertPins = call.argument<Map<String, String>>("trustedCertPins")

                    val prefs = getSharedPreferences(AutoBackupJobService.PREFS_NAME, Context.MODE_PRIVATE)
                    val editor = prefs.edit()
                    if (call.hasArgument("serverUri")) {
                        if (serverUri.isNullOrEmpty()) {
                            editor.remove(AutoBackupJobService.KEY_SERVER_URI)
                        } else {
                            editor.putString(AutoBackupJobService.KEY_SERVER_URI, serverUri)
                        }
                    }
                    if (call.hasArgument("token")) {
                        if (token.isNullOrEmpty()) {
                            editor.remove(AutoBackupJobService.KEY_AUTH_TOKEN)
                        } else {
                            editor.putString(AutoBackupJobService.KEY_AUTH_TOKEN, token)
                        }
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
                    if (wifiOnly != null) {
                        editor.putBoolean(AutoBackupJobService.KEY_WIFI_ONLY, wifiOnly)
                    }
                    if (requireCharging != null) {
                        editor.putBoolean(AutoBackupJobService.KEY_REQUIRE_CHARGING, requireCharging)
                    }
                    if (pinnedCertPins != null) {
                        editor.putString(
                            AutoBackupJobService.KEY_TRUSTED_CERT_PINS,
                            org.json.JSONObject(pinnedCertPins).toString()
                        )
                    }
                    editor.apply()

                    if (call.hasArgument("token") && token.isNullOrEmpty()) {
                        AutoBackupJobService.cancelAll(this)
                    } else {
                        AutoBackupJobService.schedule(this)
                    }
                    result.success(true)
                }
                "isWifiConnected" -> {
                    result.success(AutoBackupJobService.isWifiConnected(this))
                }
                "isDeviceCharging" -> {
                    result.success(AutoBackupJobService.isDeviceCharging(this))
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

        // Arm background AutoBackupJobService on app start only when authenticated
        try {
            if (AutoBackupJobService.hasAuthConfig(this)) {
                AutoBackupJobService.schedule(this)
            }
        } catch (_: Exception) {}
    }

    private fun deleteDeviceMediaFile(filePath: String, result: MethodChannel.Result) {
        val file = File(filePath)
        if (!file.exists()) {
            mainHandler.post { result.success(true) }
            return
        }
        try {
            if (file.delete()) {
                mainHandler.post { result.success(true) }
                return
            }
        } catch (_: Exception) {}

        // Scoped Storage fallback: find MediaStore URI matching _DATA and request deletion
        val mediaUri = findMediaStoreUriByPath(filePath)
        if (mediaUri == null) {
            mainHandler.post { result.success(false) }
            return
        }

        try {
            val rows = contentResolver.delete(mediaUri, null, null)
            if (rows > 0 || !file.exists()) {
                mainHandler.post { result.success(true) }
                return
            }
        } catch (se: SecurityException) {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q &&
                tryHandleRecoverableSecurityException(se, result)
            ) {
                return
            }
        } catch (_: Exception) {}

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            mainHandler.post {
                if (pendingDeleteResult != null) {
                    result.success(false)
                    return@post
                }
                pendingDeleteResult = result
                try {
                    val pi = MediaStore.createDeleteRequest(contentResolver, listOf(mediaUri))
                    startIntentSenderForResult(pi.intentSender, REQUEST_CODE_DELETE_MEDIA, null, 0, 0, 0)
                } catch (_: Exception) {
                    pendingDeleteResult = null
                    result.success(false)
                }
            }
            return
        }

        mainHandler.post { result.success(false) }
    }

    @android.annotation.TargetApi(Build.VERSION_CODES.Q)
    private fun tryHandleRecoverableSecurityException(
        se: SecurityException,
        result: MethodChannel.Result
    ): Boolean {
        val rse = se as? RecoverableSecurityException ?: return false
        mainHandler.post {
            if (pendingDeleteResult != null) {
                result.success(false)
                return@post
            }
            pendingDeleteResult = result
            try {
                startIntentSenderForResult(
                    rse.userAction.actionIntent.intentSender,
                    REQUEST_CODE_DELETE_MEDIA,
                    null, 0, 0, 0
                )
            } catch (_: Exception) {
                pendingDeleteResult = null
                result.success(false)
            }
        }
        return true
    }

    private fun findMediaStoreUriByPath(filePath: String): Uri? {
        val collections = listOf(
            MediaStore.Images.Media.EXTERNAL_CONTENT_URI,
            MediaStore.Video.Media.EXTERNAL_CONTENT_URI
        )
        val proj = arrayOf(MediaStore.MediaColumns._ID)
        for (collection in collections) {
            try {
                contentResolver.query(
                    collection,
                    proj,
                    "${MediaStore.MediaColumns.DATA} = ?",
                    arrayOf(filePath),
                    null
                )?.use { cursor ->
                    if (cursor.moveToFirst()) {
                        val idCol = cursor.getColumnIndex(MediaStore.MediaColumns._ID)
                        if (idCol != -1) {
                            val id = cursor.getLong(idCol)
                            return ContentUris.withAppendedId(collection, id)
                        }
                    }
                }
            } catch (_: Exception) {}
        }
        return null
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
        ioExecutor.shutdown()
        super.onDestroy()
    }

    private fun checkStoragePermission(): Boolean {
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

    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == REQUEST_CODE_MEDIA_PERMISSION) {
            val granted = grantResults.isNotEmpty() && grantResults.any { it == PackageManager.PERMISSION_GRANTED }
            permissionResult?.success(granted)
            permissionResult = null
        }
    }

    @Deprecated("Deprecated in Java")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == REQUEST_CODE_DELETE_MEDIA) {
            pendingDeleteResult?.success(resultCode == Activity.RESULT_OK)
            pendingDeleteResult = null
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
            val dataCol = cursor.getColumnIndex(MediaStore.MediaColumns.DATA)
            val nameCol = cursor.getColumnIndex(MediaStore.MediaColumns.DISPLAY_NAME)
            val sizeCol = cursor.getColumnIndex(MediaStore.MediaColumns.SIZE)
            val mimeCol = cursor.getColumnIndex(MediaStore.MediaColumns.MIME_TYPE)
            val modCol = cursor.getColumnIndex(MediaStore.MediaColumns.DATE_MODIFIED)
            val takenCol = cursor.getColumnIndex(MediaStore.Images.Media.DATE_TAKEN)
            val pendingCol = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) cursor.getColumnIndex(MediaStore.MediaColumns.IS_PENDING) else -1
            val trashedCol = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) cursor.getColumnIndex(MediaStore.MediaColumns.IS_TRASHED) else -1

            while (cursor.moveToNext() && result.size < 200) {
                if (pendingCol != -1 && cursor.getInt(pendingCol) == 1) continue
                if (trashedCol != -1 && cursor.getInt(trashedCol) == 1) continue
                if (dataCol == -1 || sizeCol == -1) continue

                val path = if (!cursor.isNull(dataCol)) cursor.getString(dataCol) else null
                if (path.isNullOrEmpty()) continue
                val name = if (nameCol != -1 && !cursor.isNull(nameCol)) cursor.getString(nameCol) else File(path).name
                if (name.startsWith(".") || name.contains(".trashed") || name.contains(".pending") || File(path).name.startsWith(".")) {
                    continue
                }

                val size = cursor.getLong(sizeCol)
                val mime = if (mimeCol != -1 && !cursor.isNull(mimeCol)) cursor.getString(mimeCol) else "image/jpeg"
                val dateTaken = if (takenCol != -1 && !cursor.isNull(takenCol)) cursor.getLong(takenCol) else 0L
                val dateModified = if (modCol != -1 && !cursor.isNull(modCol)) cursor.getLong(modCol) * 1000L else 0L
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
            val dataCol = cursor.getColumnIndex(MediaStore.MediaColumns.DATA)
            val nameCol = cursor.getColumnIndex(MediaStore.MediaColumns.DISPLAY_NAME)
            val sizeCol = cursor.getColumnIndex(MediaStore.MediaColumns.SIZE)
            val mimeCol = cursor.getColumnIndex(MediaStore.MediaColumns.MIME_TYPE)
            val modCol = cursor.getColumnIndex(MediaStore.MediaColumns.DATE_MODIFIED)
            val takenCol = cursor.getColumnIndex(MediaStore.Video.Media.DATE_TAKEN)
            val pendingCol = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) cursor.getColumnIndex(MediaStore.MediaColumns.IS_PENDING) else -1
            val trashedCol = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) cursor.getColumnIndex(MediaStore.MediaColumns.IS_TRASHED) else -1

            while (cursor.moveToNext() && result.size < 300) {
                if (pendingCol != -1 && cursor.getInt(pendingCol) == 1) continue
                if (trashedCol != -1 && cursor.getInt(trashedCol) == 1) continue
                if (dataCol == -1 || sizeCol == -1) continue

                val path = if (!cursor.isNull(dataCol)) cursor.getString(dataCol) else null
                if (path.isNullOrEmpty()) continue
                val name = if (nameCol != -1 && !cursor.isNull(nameCol)) cursor.getString(nameCol) else File(path).name
                if (name.startsWith(".") || name.contains(".trashed") || name.contains(".pending") || File(path).name.startsWith(".")) {
                    continue
                }

                val size = cursor.getLong(sizeCol)
                val mime = if (mimeCol != -1 && !cursor.isNull(mimeCol)) cursor.getString(mimeCol) else "video/mp4"
                val dateTaken = if (takenCol != -1 && !cursor.isNull(takenCol)) cursor.getLong(takenCol) else 0L
                val dateModified = if (modCol != -1 && !cursor.isNull(modCol)) cursor.getLong(modCol) * 1000L else 0L
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
