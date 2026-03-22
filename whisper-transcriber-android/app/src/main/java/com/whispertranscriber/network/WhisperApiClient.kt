package com.whispertranscriber.network

import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.MultipartBody
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.asRequestBody
import java.io.File
import java.util.concurrent.TimeUnit

/**
 * Client for sending audio files to a Whisper ASR server.
 *
 * Supports common Whisper server APIs:
 * - whisper-asr-webservice (default): POST /asr with multipart form
 * - OpenAI-compatible: POST /v1/audio/transcriptions
 */
class WhisperApiClient(
    private val serverUrl: String,
    private val endpoint: String = "/asr",
    private val apiKey: String = "",
    private val language: String = "en",
    private val outputFormat: String = "txt",
    private val timeoutSeconds: Long = 30
) {

    private val client = OkHttpClient.Builder()
        .connectTimeout(timeoutSeconds, TimeUnit.SECONDS)
        .writeTimeout(timeoutSeconds, TimeUnit.SECONDS)
        .readTimeout(60, TimeUnit.SECONDS) // transcription can take a while
        .build()

    /**
     * Sends an audio file for transcription and returns the text result.
     */
    suspend fun transcribe(audioFile: File): Result<String> = withContext(Dispatchers.IO) {
        try {
            val url = serverUrl.trimEnd('/') + endpoint

            val requestBody = MultipartBody.Builder()
                .setType(MultipartBody.FORM)
                .addFormDataPart(
                    "audio_file",
                    audioFile.name,
                    audioFile.asRequestBody("audio/wav".toMediaType())
                )
                .apply {
                    if (language.isNotBlank()) {
                        addFormDataPart("language", language)
                    }
                    if (outputFormat.isNotBlank()) {
                        addFormDataPart("output", outputFormat)
                    }
                }
                .build()

            val requestBuilder = Request.Builder()
                .url(url)
                .post(requestBody)

            if (apiKey.isNotBlank()) {
                requestBuilder.addHeader("Authorization", "Bearer $apiKey")
            }

            val response = client.newCall(requestBuilder.build()).execute()

            if (response.isSuccessful) {
                val body = response.body?.string()?.trim() ?: ""
                Result.success(body)
            } else {
                val errorBody = response.body?.string() ?: "Unknown error"
                Result.failure(Exception("Server error ${response.code}: $errorBody"))
            }
        } catch (e: Exception) {
            Result.failure(e)
        }
    }
}
