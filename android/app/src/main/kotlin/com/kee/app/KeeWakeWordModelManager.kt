package com.kee.app

import android.content.Context
import java.io.BufferedInputStream
import java.io.File
import java.io.FileOutputStream
import java.net.HttpURLConnection
import java.net.URL
import java.util.zip.ZipInputStream

object KeeWakeWordModelManager {
    private const val MODEL_NAME = "vosk-model-small-en-us-0.15"
    private const val MODEL_URL = "https://alphacephei.com/vosk/models/$MODEL_NAME.zip"

    fun getModelDir(context: Context): File = File(context.filesDir, MODEL_NAME)

    fun isModelReady(context: Context): Boolean {
        val dir = getModelDir(context)
        return dir.exists() && dir.isDirectory && File(dir, "am").exists() && File(dir, "conf").exists()
    }

    fun downloadAndExtract(
        context: Context,
        onProgress: (Int) -> Unit,
        onComplete: (Boolean, String?) -> Unit
    ) {
        if (isModelReady(context)) {
            onProgress(100)
            onComplete(true, null)
            return
        }

        Thread {
            val zipFile = File(context.cacheDir, "$MODEL_NAME.zip")
            val targetDir = getModelDir(context)
            try {
                if (targetDir.exists()) {
                    targetDir.deleteRecursively()
                }
                if (zipFile.exists()) {
                    zipFile.delete()
                }

                var connection = URL(MODEL_URL).openConnection() as HttpURLConnection
                connection.instanceFollowRedirects = true
                connection.connectTimeout = 20000
                connection.readTimeout = 30000
                connection.connect()

                // Handle manual redirect if protocol changes (http <-> https)
                var redirects = 0
                while (connection.responseCode in 300..399 && redirects < 5) {
                    val location = connection.getHeaderField("Location") ?: break
                    connection.disconnect()
                    connection = URL(location).openConnection() as HttpURLConnection
                    connection.instanceFollowRedirects = true
                    connection.connectTimeout = 20000
                    connection.readTimeout = 30000
                    connection.connect()
                    redirects++
                }

                if (connection.responseCode !in 200..299) {
                    onComplete(false, "Download failed (HTTP ${connection.responseCode})")
                    return@Thread
                }

                val totalBytes = connection.contentLengthLong
                var downloadedBytes = 0L
                var lastReported = -1

                BufferedInputStream(connection.inputStream, 16384).use { input ->
                    FileOutputStream(zipFile).use { output ->
                        val buffer = ByteArray(16384)
                        var read: Int
                        while (input.read(buffer).also { read = it } != -1) {
                            output.write(buffer, 0, read)
                            downloadedBytes += read
                            if (totalBytes > 0) {
                                // Reserve 0..85% for download, 85..100% for extraction
                                val pct = ((downloadedBytes * 85) / totalBytes).toInt().coerceIn(0, 85)
                                if (pct != lastReported) {
                                    lastReported = pct
                                    onProgress(pct)
                                }
                            }
                        }
                    }
                }
                connection.disconnect()

                onProgress(90)

                // Extract zip into context.filesDir (the zip contains top-level folder vosk-model-small-en-us-0.15/)
                ZipInputStream(BufferedInputStream(zipFile.inputStream(), 16384)).use { zis ->
                    val canonicalRoot = context.filesDir.canonicalPath + File.separator
                    var entry = zis.nextEntry
                    val buffer = ByteArray(16384)
                    while (entry != null) {
                        val outFile = File(context.filesDir, entry.name)
                        if (!outFile.canonicalPath.startsWith(canonicalRoot)) {
                            throw SecurityException("Invalid zip entry: ${entry.name}")
                        }
                        if (entry.isDirectory) {
                            outFile.mkdirs()
                        } else {
                            outFile.parentFile?.mkdirs()
                            FileOutputStream(outFile).use { fos ->
                                var len: Int
                                while (zis.read(buffer).also { len = it } != -1) {
                                    fos.write(buffer, 0, len)
                                }
                            }
                        }
                        zis.closeEntry()
                        entry = zis.nextEntry
                    }
                }

                zipFile.delete()

                if (isModelReady(context)) {
                    onProgress(100)
                    onComplete(true, null)
                } else {
                    targetDir.deleteRecursively()
                    onComplete(false, "Extracted model files are incomplete.")
                }
            } catch (e: Exception) {
                if (zipFile.exists()) zipFile.delete()
                if (targetDir.exists()) targetDir.deleteRecursively()
                onComplete(false, e.localizedMessage ?: "Failed to download wake-word model.")
            }
        }.start()
    }
}
