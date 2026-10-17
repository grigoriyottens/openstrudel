package app.openstrudel

import android.content.Context
import android.media.MediaRecorder
import android.os.Build
import java.io.File
import java.util.UUID

/** Records only after the microphone action; never starts a background service. */
class VoiceCapture(private val context: Context) {
    private var recorder: MediaRecorder? = null
    private var path: File? = null
    var startedAt: Long = 0
        private set

    val recording
        get() = recorder != null

    fun start() {
        check(recorder == null)
        val folder = File(context.noBackupFilesDir, "draft-files").apply { mkdirs() }
        val target = File(folder, UUID.randomUUID().toString() + ".m4a")
        @Suppress("DEPRECATION")
        val r = if (Build.VERSION.SDK_INT >= 31) MediaRecorder(context) else MediaRecorder()
        try {
            r.setAudioSource(MediaRecorder.AudioSource.MIC)
            r.setOutputFormat(MediaRecorder.OutputFormat.MPEG_4)
            r.setAudioEncoder(MediaRecorder.AudioEncoder.AAC)
            r.setAudioSamplingRate(44100)
            r.setAudioEncodingBitRate(96000)
            r.setMaxFileSize(18L * 1024 * 1024)
            r.setOutputFile(target.path)
            r.prepare()
            r.start()
            recorder = r
            path = target
            startedAt = System.currentTimeMillis()
        } catch (e: Exception) {
            r.release()
            target.delete()
            throw e
        }
    }

    fun level(): Float = runCatching { (recorder?.maxAmplitude ?: 0) / 32768f }.getOrDefault(0f)

    fun stop(discard: Boolean = false): LocalFile? {
        val r = recorder ?: return null
        val file = path
        recorder = null
        path = null
        val valid = runCatching {
            r.stop()
            true
        }
            .getOrDefault(false)
        r.release()
        if (discard || !valid || file == null || file.length() < 100) {
            file?.delete()
            return null
        }
        return LocalFile(
            name = "Диктовка.m4a",
            mimeType = "audio/mp4",
            path = file.path,
            size = file.length(),
        )
    }
}
