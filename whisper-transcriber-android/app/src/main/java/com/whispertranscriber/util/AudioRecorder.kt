package com.whispertranscriber.util

import android.media.AudioFormat
import android.media.AudioRecord
import android.media.MediaRecorder
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.isActive
import kotlinx.coroutines.withContext
import java.io.ByteArrayOutputStream
import java.io.File
import java.io.FileOutputStream
import java.nio.ByteBuffer
import java.nio.ByteOrder

/**
 * Records audio from the microphone and produces a WAV file.
 */
class AudioRecorder {

    companion object {
        private const val SAMPLE_RATE = 16000
        private const val CHANNEL_CONFIG = AudioFormat.CHANNEL_IN_MONO
        private const val AUDIO_FORMAT = AudioFormat.ENCODING_PCM_16BIT
    }

    private var audioRecord: AudioRecord? = null
    @Volatile
    private var isRecording = false

    private val pcmBuffer = ByteArrayOutputStream()

    fun startRecording() {
        val bufferSize = AudioRecord.getMinBufferSize(SAMPLE_RATE, CHANNEL_CONFIG, AUDIO_FORMAT)
        audioRecord = AudioRecord(
            MediaRecorder.AudioSource.MIC,
            SAMPLE_RATE,
            CHANNEL_CONFIG,
            AUDIO_FORMAT,
            bufferSize * 2
        )
        pcmBuffer.reset()
        isRecording = true
        audioRecord?.startRecording()
    }

    /**
     * Must be called from a coroutine — reads audio data in a loop.
     */
    suspend fun readLoop() = withContext(Dispatchers.IO) {
        val bufferSize = AudioRecord.getMinBufferSize(SAMPLE_RATE, CHANNEL_CONFIG, AUDIO_FORMAT)
        val buffer = ByteArray(bufferSize)
        while (isActive && isRecording) {
            val read = audioRecord?.read(buffer, 0, buffer.size) ?: -1
            if (read > 0) {
                pcmBuffer.write(buffer, 0, read)
            }
        }
    }

    /**
     * Stops recording and returns the audio as a WAV file.
     */
    fun stopRecording(outputFile: File): File {
        isRecording = false
        audioRecord?.stop()
        audioRecord?.release()
        audioRecord = null

        val pcmData = pcmBuffer.toByteArray()
        pcmBuffer.reset()

        // Write WAV file
        FileOutputStream(outputFile).use { fos ->
            writeWavHeader(fos, pcmData.size)
            fos.write(pcmData)
        }
        return outputFile
    }

    fun isCurrentlyRecording(): Boolean = isRecording

    fun cancel() {
        isRecording = false
        try {
            audioRecord?.stop()
        } catch (_: Exception) {}
        audioRecord?.release()
        audioRecord = null
        pcmBuffer.reset()
    }

    private fun writeWavHeader(out: FileOutputStream, pcmDataLength: Int) {
        val totalDataLen = pcmDataLength + 36
        val channels = 1
        val bitsPerSample = 16
        val byteRate = SAMPLE_RATE * channels * bitsPerSample / 8

        val header = ByteBuffer.allocate(44).apply {
            order(ByteOrder.LITTLE_ENDIAN)
            // RIFF header
            put("RIFF".toByteArray())
            putInt(totalDataLen)
            put("WAVE".toByteArray())
            // fmt subchunk
            put("fmt ".toByteArray())
            putInt(16) // subchunk size
            putShort(1) // PCM format
            putShort(channels.toShort())
            putInt(SAMPLE_RATE)
            putInt(byteRate)
            putShort((channels * bitsPerSample / 8).toShort()) // block align
            putShort(bitsPerSample.toShort())
            // data subchunk
            put("data".toByteArray())
            putInt(pcmDataLength)
        }
        out.write(header.array())
    }
}
