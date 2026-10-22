package ahmedelsapagh.com.whiteboard

import android.app.Activity
import android.content.Intent
import android.provider.OpenableColumns
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream
import java.util.concurrent.Executors

class MainActivity : FlutterActivity() {
    private val maximumBytes = 128 * 1024 * 1024
    private val requestCode = 0x424c
    private val worker = Executors.newSingleThreadExecutor()
    private data class Operation(val kind: String, val result: MethodChannel.Result, val bytes: ByteArray? = null)
    private var pending: Operation? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        for (name in listOf("blanko/image_picker", "blanko/project_files")) {
            MethodChannel(flutterEngine.dartExecutor.binaryMessenger, name).setMethodCallHandler { call, result ->
                if (call.method !in listOf("pickImage", "pickProject", "saveFile")) {
                    result.notImplemented()
                } else if (pending != null) {
                    result.error("busy", "Another file operation is in progress.", null)
                } else {
                    val save = call.method == "saveFile"
                    val bytes = call.argument<ByteArray>("bytes")
                    val extension = call.argument<String>("extension")
                    if (save && (bytes == null || bytes.isEmpty() || bytes.size > maximumBytes || extension !in listOf("png", "wboard"))) {
                        result.error("invalid_file", "Unsupported file type or file exceeds the 128 MiB limit.", null)
                        return@setMethodCallHandler
                    }
                    val intent = Intent(if (save) Intent.ACTION_CREATE_DOCUMENT else Intent.ACTION_OPEN_DOCUMENT).apply {
                        addCategory(Intent.CATEGORY_OPENABLE)
                        type = if (save) { if (extension == "png") "image/png" else "application/octet-stream" } else if (call.method == "pickImage") "image/*" else "*/*"
                        if (call.method == "pickImage") putExtra(Intent.EXTRA_MIME_TYPES, arrayOf("image/png", "image/jpeg"))
                        if (save) {
                            val name = (call.argument<String>("suggestedName") ?: "Blanko.$extension")
                                .map { if (it == '/' || it == '\\' || it.code == 0) '_' else it }.joinToString("")
                            putExtra(Intent.EXTRA_TITLE, if (name.endsWith(".$extension", true)) name else "$name.$extension")
                        }
                    }
                    pending = Operation(call.method, result, if (save) bytes else null)
                    try { startActivityForResult(intent, requestCode) }
                    catch (error: Exception) { finish(pending!!, "unavailable", error.localizedMessage ?: "No document picker is available.") }
                }
            }
        }
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != this.requestCode) return
        val operation = pending ?: return
        if (resultCode != Activity.RESULT_OK) {
            pending = null
            operation.result.success(if (operation.kind == "saveFile") false else null)
            return
        }
        val uri = data?.data
        if (uri == null) { finish(operation, "invalid_file", "The document provider returned no file."); return }
        worker.execute {
            try {
                val value: Any = if (operation.kind == "saveFile") {
                    val output = contentResolver.openOutputStream(uri, "wt") ?: error("Could not open the destination.")
                    output.use { it.write(operation.bytes!!) }
                    true
                } else {
                    val limit = if (operation.kind == "pickImage") 16 * 1024 * 1024 else 64 * 1024 * 1024
                    var filename = uri.lastPathSegment ?: "Selected file"
                    contentResolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME, OpenableColumns.SIZE), null, null, null)?.use { cursor ->
                        if (cursor.moveToFirst()) {
                            if (!cursor.isNull(0)) filename = cursor.getString(0)
                            if (!cursor.isNull(1) && cursor.getLong(1) > limit) error("File exceeds the ${limit / 1024 / 1024} MiB import limit.")
                        }
                    }
                    val mime = contentResolver.getType(uri)
                    if (operation.kind == "pickProject" && !filename.endsWith(".wboard", true)) error("Select a .wboard project file.")
                    if (operation.kind == "pickImage" && mime !in listOf("image/png", "image/jpeg")) error("Select a PNG or JPEG image.")
                    val input = contentResolver.openInputStream(uri) ?: error("Could not open the selected file.")
                    val bytes = input.use { stream ->
                        val output = ByteArrayOutputStream()
                        val buffer = ByteArray(64 * 1024)
                        while (true) {
                            val count = stream.read(buffer)
                            if (count < 0) break
                            if (output.size() + count > limit) error("File exceeds the ${limit / 1024 / 1024} MiB import limit.")
                            output.write(buffer, 0, count)
                        }
                        output.toByteArray()
                    }
                    if (bytes.isEmpty()) error("The selected file is empty.")
                    if (operation.kind == "pickImage") mapOf("bytes" to bytes, "filename" to filename, "mimeType" to mime) else bytes
                }
                runOnUiThread { if (pending === operation) { pending = null; operation.result.success(value) } }
            } catch (error: Exception) {
                runOnUiThread { finish(operation, if (operation.kind == "saveFile") "write_failed" else "read_failed", error.localizedMessage ?: "File operation failed.") }
            }
        }
    }

    private fun finish(operation: Operation, code: String, message: String) {
        if (pending !== operation) return
        pending = null
        operation.result.error(code, message, null)
    }

    override fun onDestroy() {
        pending?.let { finish(it, "unavailable", "The editor closed before the file operation completed.") }
        worker.shutdown()
        super.onDestroy()
    }
}
