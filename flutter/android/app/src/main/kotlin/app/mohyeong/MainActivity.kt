package app.mohyeong

import android.Manifest
import android.app.Activity
import android.content.ClipData
import android.content.ClipboardManager
import android.content.ContentValues
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.PowerManager
import android.provider.DocumentsContract
import android.provider.MediaStore
import android.provider.Settings
import android.view.KeyEvent
import android.view.WindowManager
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

// FlutterFragmentActivity (rather than FlutterActivity) is required by the
// local_auth plugin so the biometric prompt can attach to a FragmentManager.
class MainActivity : FlutterFragmentActivity() {

    private val secureFlagChannel = "app.mohyeong/secure_flag"
    private val safChannel = "app.mohyeong/saf"
    private val permissionsChannel = "app.mohyeong/permissions"
    private val volumeKeysChannel = "app.mohyeong/volume_keys"
    private val imageActionsChannel = "app.mohyeong/image_actions"

    // When true, the reader is consuming hardware volume keys for page
    // navigation; we forward each press to Dart and suppress the system
    // volume UI. Toggled from Dart via the volume_keys channel.
    private var volumeKeysEnabled = false
    private var volumeChannel: MethodChannel? = null

    // The OpenDocumentTree call is async: we stash the in-flight Dart result
    // and resolve it in onActivityResult once the picker returns.
    private var pendingTreeResult: MethodChannel.Result? = null

    // The POST_NOTIFICATIONS runtime request is likewise async; resolved in
    // onRequestPermissionsResult.
    private var pendingNotificationResult: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, secureFlagChannel)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "setSecure" -> {
                        val secure = call.arguments as? Boolean ?: false
                        runOnUiThread {
                            if (secure) {
                                window.addFlags(WindowManager.LayoutParams.FLAG_SECURE)
                            } else {
                                window.clearFlags(WindowManager.LayoutParams.FLAG_SECURE)
                            }
                            // Reply only after the flag has actually been applied on
                            // the UI thread, so the Dart future can't resolve early.
                            result.success(null)
                        }
                    }

                    // Reader "Show content in cutout area" (Mihon
                    // `cutout_short` / drawUnderCutout): SHORT_EDGES lets the
                    // fullscreen reader draw beneath the display notch instead
                    // of letterboxing it. API 28+ only; a no-op before that.
                    "setCutoutShortEdges" -> {
                        val shortEdges = call.arguments as? Boolean ?: false
                        runOnUiThread {
                            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                                window.attributes = window.attributes.apply {
                                    layoutInDisplayCutoutMode = if (shortEdges) {
                                        WindowManager.LayoutParams
                                            .LAYOUT_IN_DISPLAY_CUTOUT_MODE_SHORT_EDGES
                                    } else {
                                        WindowManager.LayoutParams
                                            .LAYOUT_IN_DISPLAY_CUTOUT_MODE_DEFAULT
                                    }
                                }
                            }
                            result.success(null)
                        }
                    }
                    else -> result.notImplemented()
                }
            }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, safChannel)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    // Launch the system folder picker. Resolves to the persisted
                    // tree URI string, or null if the user cancelled. Mirrors
                    // Mihon's storageLocationPicker (OpenDocumentTree +
                    // takePersistableUriPermission).
                    "openTree" -> {
                        if (pendingTreeResult != null) {
                            result.error("BUSY", "A folder picker is already open", null)
                            return@setMethodCallHandler
                        }
                        pendingTreeResult = result
                        try {
                            val intent = Intent(Intent.ACTION_OPEN_DOCUMENT_TREE)
                            startActivityForResult(intent, OPEN_TREE_REQUEST)
                        } catch (e: Exception) {
                            pendingTreeResult = null
                            result.error("PICK_FAILED", e.message, null)
                        }
                    }

                    // List the immediate children of a tree URI (root) or a
                    // tree-based document URI (sub-folder). Returns a list of
                    // maps: { name, uri, isDir, size, mime }.
                    "listChildren" -> {
                        val uriString = call.argument<String>("uri")
                        if (uriString == null) {
                            result.error("BAD_ARGS", "uri is required", null)
                            return@setMethodCallHandler
                        }
                        try {
                            result.success(listChildren(uriString))
                        } catch (e: Exception) {
                            result.error("LIST_FAILED", e.message, null)
                        }
                    }

                    // Read the full bytes of a document URI.
                    "readBytes" -> {
                        val uriString = call.argument<String>("uri")
                        if (uriString == null) {
                            result.error("BAD_ARGS", "uri is required", null)
                            return@setMethodCallHandler
                        }
                        try {
                            val bytes = contentResolver.openInputStream(Uri.parse(uriString))
                                ?.use { it.readBytes() }
                            result.success(bytes)
                        } catch (e: Exception) {
                            result.error("READ_FAILED", e.message, null)
                        }
                    }

                    // Human-readable name of a tree URI for display in settings /
                    // onboarding (mirrors UniFile.displayablePath, best-effort).
                    "displayName" -> {
                        val uriString = call.argument<String>("uri")
                        if (uriString == null) {
                            result.error("BAD_ARGS", "uri is required", null)
                            return@setMethodCallHandler
                        }
                        result.success(displayName(uriString))
                    }

                    // Available/total bytes of the volume holding the app's
                    // data dir (StatFs — backs the Storage usage bar, like
                    // Mihon's StorageInfo composable).
                    "storageStats" -> {
                        try {
                            val stat = android.os.StatFs(filesDir.absolutePath)
                            result.success(
                                mapOf(
                                    "available" to stat.availableBytes,
                                    "total" to stat.totalBytes,
                                )
                            )
                        } catch (e: Exception) {
                            result.error("STAT_FAILED", e.message, null)
                        }
                    }

                    // Whether a persisted permission for this tree URI still
                    // exists (the user could have revoked it in system settings).
                    "hasPermission" -> {
                        val uriString = call.argument<String>("uri")
                        if (uriString == null) {
                            result.error("BAD_ARGS", "uri is required", null)
                            return@setMethodCallHandler
                        }
                        val target = Uri.parse(uriString)
                        val granted = contentResolver.persistedUriPermissions.any {
                            it.uri == target && it.isReadPermission
                        }
                        result.success(granted)
                    }

                    else -> result.notImplemented()
                }
            }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, permissionsChannel)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    // POST_NOTIFICATIONS is only a runtime permission on
                    // Android 13 (TIRAMISU)+. Below that it's granted by
                    // install, so report true.
                    "hasNotificationPermission" -> {
                        val granted = Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU ||
                            ContextCompat.checkSelfPermission(
                                this,
                                Manifest.permission.POST_NOTIFICATIONS,
                            ) == PackageManager.PERMISSION_GRANTED
                        result.success(granted)
                    }

                    "requestNotificationPermission" -> {
                        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) {
                            result.success(true)
                            return@setMethodCallHandler
                        }
                        if (ContextCompat.checkSelfPermission(
                                this,
                                Manifest.permission.POST_NOTIFICATIONS,
                            ) == PackageManager.PERMISSION_GRANTED
                        ) {
                            result.success(true)
                            return@setMethodCallHandler
                        }
                        if (pendingNotificationResult != null) {
                            result.error("BUSY", "A permission request is in flight", null)
                            return@setMethodCallHandler
                        }
                        pendingNotificationResult = result
                        ActivityCompat.requestPermissions(
                            this,
                            arrayOf(Manifest.permission.POST_NOTIFICATIONS),
                            NOTIFICATION_REQUEST,
                        )
                    }

                    "isIgnoringBatteryOptimizations" -> {
                        val pm = getSystemService(POWER_SERVICE) as PowerManager
                        result.success(pm.isIgnoringBatteryOptimizations(packageName))
                    }

                    "requestIgnoreBatteryOptimizations" -> {
                        try {
                            // Mirrors Mihon: a settings dialog, not an
                            // activity-result flow. The Dart side re-checks
                            // the grant on resume.
                            val intent = Intent(
                                Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS,
                                Uri.parse("package:$packageName"),
                            )
                            startActivity(intent)
                            result.success(null)
                        } catch (e: Exception) {
                            result.error("INTENT_FAILED", e.message, null)
                        }
                    }

                    else -> result.notImplemented()
                }
            }

        // Reader page-image actions (Mihon ReaderPageActionsDialog backends):
        // share via ACTION_SEND chooser, copy the image itself to the
        // clipboard (ClipData.newUri, like ReaderActivity.onCopyImageResult),
        // and save into Pictures/<app label> through MediaStore (the modern
        // equivalent of Mihon's ImageSaver Location.Pictures, no storage
        // permission needed on API 29+). The staged file lives in cacheDir,
        // exposed through the manifest FileProvider.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, imageActionsChannel)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "share" -> {
                        val path = call.argument<String>("path")
                        val message = call.argument<String>("message")
                        if (path == null) {
                            result.error("BAD_ARGS", "path is required", null)
                            return@setMethodCallHandler
                        }
                        try {
                            val uri = FileProvider.getUriForFile(
                                this,
                                "$packageName.fileprovider",
                                File(path),
                            )
                            val intent = Intent(Intent.ACTION_SEND).apply {
                                type = "image/*"
                                putExtra(Intent.EXTRA_STREAM, uri)
                                if (message != null) putExtra(Intent.EXTRA_TEXT, message)
                                clipData = ClipData.newRawUri(null, uri)
                                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                            }
                            startActivity(Intent.createChooser(intent, null))
                            result.success(null)
                        } catch (e: Exception) {
                            result.error("SHARE_FAILED", e.message, null)
                        }
                    }

                    "shareText" -> {
                        val text = call.argument<String>("text")
                        if (text == null) {
                            result.error("BAD_ARGS", "text is required", null)
                            return@setMethodCallHandler
                        }
                        try {
                            val intent = Intent(Intent.ACTION_SEND).apply {
                                type = "text/plain"
                                putExtra(Intent.EXTRA_TEXT, text)
                            }
                            startActivity(Intent.createChooser(intent, null))
                            result.success(null)
                        } catch (e: Exception) {
                            result.error("SHARE_FAILED", e.message, null)
                        }
                    }

                    "copyToClipboard" -> {
                        val path = call.argument<String>("path")
                        if (path == null) {
                            result.error("BAD_ARGS", "path is required", null)
                            return@setMethodCallHandler
                        }
                        try {
                            val uri = FileProvider.getUriForFile(
                                this,
                                "$packageName.fileprovider",
                                File(path),
                            )
                            val clipboard = getSystemService(CLIPBOARD_SERVICE) as ClipboardManager
                            clipboard.setPrimaryClip(ClipData.newUri(contentResolver, "", uri))
                            result.success(null)
                        } catch (e: Exception) {
                            result.error("COPY_FAILED", e.message, null)
                        }
                    }

                    "saveToPictures" -> {
                        val path = call.argument<String>("path")
                        val displayName = call.argument<String>("displayName")
                        val mime = call.argument<String>("mime") ?: "image/png"
                        if (path == null || displayName == null) {
                            result.error("BAD_ARGS", "path and displayName are required", null)
                            return@setMethodCallHandler
                        }
                        try {
                            val appLabel = applicationInfo.loadLabel(packageManager).toString()
                            val values = ContentValues().apply {
                                put(MediaStore.Images.Media.DISPLAY_NAME, displayName)
                                put(MediaStore.Images.Media.MIME_TYPE, mime)
                                put(
                                    MediaStore.Images.Media.RELATIVE_PATH,
                                    "${android.os.Environment.DIRECTORY_PICTURES}/$appLabel",
                                )
                            }
                            val uri = contentResolver.insert(
                                MediaStore.Images.Media.EXTERNAL_CONTENT_URI,
                                values,
                            ) ?: throw IllegalStateException("MediaStore insert returned null")
                            contentResolver.openOutputStream(uri)?.use { out ->
                                File(path).inputStream().use { it.copyTo(out) }
                            } ?: throw IllegalStateException("openOutputStream returned null")
                            result.success(uri.toString())
                        } catch (e: Exception) {
                            result.error("SAVE_FAILED", e.message, null)
                        }
                    }

                    else -> result.notImplemented()
                }
            }

        volumeChannel =
            MethodChannel(flutterEngine.dartExecutor.binaryMessenger, volumeKeysChannel)
        volumeChannel!!.setMethodCallHandler { call, result ->
            when (call.method) {
                "setEnabled" -> {
                    volumeKeysEnabled = call.arguments as? Boolean ?: false
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }

    // Intercept the hardware volume keys while the reader has enabled them.
    // Forward each key-down (ignoring auto-repeat) to Dart and consume both
    // the down and up events so the system volume overlay never appears.
    // Mirrors Mihon, where the reader turns pages with the volume keys.
    override fun dispatchKeyEvent(event: KeyEvent): Boolean {
        if (volumeKeysEnabled) {
            val code = event.keyCode
            if (code == KeyEvent.KEYCODE_VOLUME_UP || code == KeyEvent.KEYCODE_VOLUME_DOWN) {
                if (event.action == KeyEvent.ACTION_DOWN && event.repeatCount == 0) {
                    val direction = if (code == KeyEvent.KEYCODE_VOLUME_UP) "up" else "down"
                    volumeChannel?.invokeMethod("volumeKey", direction)
                }
                return true
            }
        }
        return super.dispatchKeyEvent(event)
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode != NOTIFICATION_REQUEST) return
        val reply = pendingNotificationResult
        pendingNotificationResult = null
        val granted = grantResults.isNotEmpty() &&
            grantResults[0] == PackageManager.PERMISSION_GRANTED
        reply?.success(granted)
    }

    private fun listChildren(uriString: String): List<Map<String, Any?>> {
        val treeUri = Uri.parse(uriString)
        // For the root tree URI, the parent document id is the tree document id.
        // For a sub-folder document URI, it's that document's own id.
        val parentDocId = if (DocumentsContract.isDocumentUri(this, treeUri)) {
            DocumentsContract.getDocumentId(treeUri)
        } else {
            DocumentsContract.getTreeDocumentId(treeUri)
        }
        val childrenUri =
            DocumentsContract.buildChildDocumentsUriUsingTree(treeUri, parentDocId)

        val children = mutableListOf<Map<String, Any?>>()
        val projection = arrayOf(
            DocumentsContract.Document.COLUMN_DOCUMENT_ID,
            DocumentsContract.Document.COLUMN_DISPLAY_NAME,
            DocumentsContract.Document.COLUMN_MIME_TYPE,
            DocumentsContract.Document.COLUMN_SIZE,
        )
        contentResolver.query(childrenUri, projection, null, null, null)?.use { c ->
            val idIdx = c.getColumnIndexOrThrow(DocumentsContract.Document.COLUMN_DOCUMENT_ID)
            val nameIdx = c.getColumnIndexOrThrow(DocumentsContract.Document.COLUMN_DISPLAY_NAME)
            val mimeIdx = c.getColumnIndexOrThrow(DocumentsContract.Document.COLUMN_MIME_TYPE)
            val sizeIdx = c.getColumnIndexOrThrow(DocumentsContract.Document.COLUMN_SIZE)
            while (c.moveToNext()) {
                val docId = c.getString(idIdx)
                val mime = c.getString(mimeIdx)
                val childUri = DocumentsContract.buildDocumentUriUsingTree(treeUri, docId)
                children.add(
                    mapOf(
                        "name" to c.getString(nameIdx),
                        "uri" to childUri.toString(),
                        "isDir" to (mime == DocumentsContract.Document.MIME_TYPE_DIR),
                        "size" to (if (c.isNull(sizeIdx)) 0L else c.getLong(sizeIdx)),
                        "mime" to mime,
                    )
                )
            }
        }
        return children
    }

    private fun displayName(uriString: String): String {
        val uri = Uri.parse(uriString)
        // Prefer the actual display name from the provider.
        try {
            contentResolver.query(
                uri,
                arrayOf(DocumentsContract.Document.COLUMN_DISPLAY_NAME),
                null,
                null,
                null,
            )?.use { c ->
                if (c.moveToFirst() && !c.isNull(0)) return c.getString(0)
            }
        } catch (_: Exception) {
            // Fall through to the tree-id heuristic.
        }
        // Fallback: the last path segment of the tree document id
        // (e.g. "primary:Manga" -> "Manga").
        val docId = try {
            if (DocumentsContract.isDocumentUri(this, uri)) {
                DocumentsContract.getDocumentId(uri)
            } else {
                DocumentsContract.getTreeDocumentId(uri)
            }
        } catch (_: Exception) {
            return uri.lastPathSegment ?: uriString
        }
        return docId.substringAfterLast('/').substringAfterLast(':')
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != OPEN_TREE_REQUEST) return
        val reply = pendingTreeResult
        pendingTreeResult = null
        val uri = data?.data
        if (resultCode == Activity.RESULT_OK && uri != null) {
            val flags = Intent.FLAG_GRANT_READ_URI_PERMISSION or
                Intent.FLAG_GRANT_WRITE_URI_PERMISSION
            try {
                contentResolver.takePersistableUriPermission(uri, flags)
            } catch (e: SecurityException) {
                // Some OEMs (InkBook, certain Samsung builds) throw here even
                // though the grant succeeds. Mihon ignores it; so do we.
            }
            reply?.success(uri.toString())
        } else {
            reply?.success(null)
        }
    }

    companion object {
        private const val OPEN_TREE_REQUEST = 0x5AF0
        private const val NOTIFICATION_REQUEST = 0x5AF1
    }
}
