# Whisper Transcriber - Android Floating Overlay

An Android app that provides a **floating overlay bubble** (draws over other apps) for voice-to-text transcription using your self-hosted Whisper ASR server over VPN.

## How It Works

1. **Start the overlay** from the app - a floating mic bubble appears on screen
2. **Switch to any app** - the bubble stays on top
3. **Tap the bubble** to start recording audio
4. **Tap again** to stop - audio is sent to your Whisper server via VPN
5. **Transcribed text** is automatically copied to your clipboard
6. **Paste** the text wherever you need it (any text field, chat app, etc.)
7. **Long-press** the bubble to show/hide the transcription panel, or to close

## Visual States

- **Blue bubble** = idle, ready to record
- **Red bubble** = recording audio
- **Amber bubble** = sending to server / transcribing

## Setup

### 1. Server Requirements

You need a Whisper ASR server running. Compatible with:

- [whisper-asr-webservice](https://github.com/ahmetoner/whisper-asr-webservice) (default) - sends to `POST /asr`
- [faster-whisper-server](https://github.com/fedirz/faster-whisper-server)
- Any server accepting multipart audio file uploads

### 2. VPN Setup

Connect your Android device to the same VPN your server is on. The app sends audio over whatever network connection is active (including VPN).

### 3. App Configuration

Open **Settings** in the app and configure:

| Setting | Description | Example |
|---------|-------------|---------|
| Server URL | Your Whisper server address | `http://10.8.0.1:9000` |
| API Endpoint | Transcription endpoint path | `/asr` (default) |
| API Key | Optional auth key | (leave empty if none) |
| Language | Language code | `en`, `es`, `fr`, or empty for auto |
| Output Format | Response format | `txt` (default), `json`, `vtt`, `srt` |
| Connection Timeout | Seconds to wait | `30` |
| Auto-copy | Auto copy result to clipboard | On (default) |

### 4. Permissions

The app requires:
- **Microphone** - to record audio
- **Draw over other apps** - for the floating bubble overlay
- **Notifications** - for the foreground service notification
- **Internet** - to reach your Whisper server

## Building

### Prerequisites

- Android Studio Hedgehog (2023.1.1) or later
- Android SDK 34
- Kotlin 1.9+

### Build Steps

```bash
cd whisper-transcriber-android

# Debug build
./gradlew assembleDebug

# Install on connected device
./gradlew installDebug
```

Or open the project in Android Studio and run directly.

## Architecture

```
com.whispertranscriber/
  ui/
    MainActivity.kt       - Launch screen, permission handling, start/stop overlay
    SettingsActivity.kt   - Server and audio configuration
  service/
    FloatingOverlayService.kt - Foreground service with floating bubble overlay
  network/
    WhisperApiClient.kt   - OkHttp client for Whisper server API
  util/
    AudioRecorder.kt      - PCM audio recording + WAV encoding
```

## Tips

- The bubble is draggable - move it anywhere on screen
- Long-press the bubble to see the full transcription panel
- The notification shows current status and has a Stop button
- Audio is recorded at 16kHz mono WAV (optimal for Whisper)
- Cleartext HTTP is allowed for local/VPN server connections
