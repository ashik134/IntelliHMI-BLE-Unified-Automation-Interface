package com.example.rev_crane_control_ops

import android.media.AudioFormat
import android.media.AudioManager
import android.media.AudioTrack
import android.view.WindowManager
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.security.GeneralSecurityException
import java.util.concurrent.Executors
import javax.crypto.SecretKeyFactory
import javax.crypto.spec.PBEKeySpec
import kotlin.concurrent.thread
import kotlin.math.PI
import kotlin.math.min
import kotlin.math.sin

class MainActivity : FlutterFragmentActivity() {
    private val buzzerTonePlayer = BuzzerTonePlayer()
    private val securityExecutor = Executors.newSingleThreadExecutor { runnable ->
        Thread(runnable, "intellihmi-admin-kdf").apply { isDaemon = true }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            BUZZER_CHANNEL,
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "start" -> {
                    buzzerTonePlayer.start(
                        id = call.argument<String>("id") ?: DEFAULT_BUZZER_ID,
                        patternName = call.argument<String>("pattern") ?: "steady",
                        priorityName = call.argument<String>("priority") ?: "normal",
                    )
                    result.success(null)
                }

                "stop" -> {
                    buzzerTonePlayer.stop(
                        id = call.argument<String>("id") ?: DEFAULT_BUZZER_ID,
                    )
                    result.success(null)
                }

                "stopAll" -> {
                    buzzerTonePlayer.stopAll()
                    result.success(null)
                }

                else -> result.notImplemented()
            }
        }

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            FACE_SDK_CHANNEL,
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "getNativeLibDir" -> result.success(applicationInfo.nativeLibraryDir)
                else -> result.notImplemented()
            }
        }

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            SECURITY_CHANNEL,
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "setSecureScreen" -> {
                    val enabled = call.argument<Boolean>("enabled") ?: false
                    runOnUiThread {
                        if (enabled) {
                            window.addFlags(WindowManager.LayoutParams.FLAG_SECURE)
                        } else {
                            window.clearFlags(WindowManager.LayoutParams.FLAG_SECURE)
                        }
                        result.success(null)
                    }
                }

                "deriveAdminVerifier" -> {
                    val credential = call.argument<String>("credential")
                    val salt = call.argument<ByteArray>("salt")
                    val iterations = call.argument<Int>("iterations")
                    val outputBytes = call.argument<Int>("outputBytes")
                    if (
                        credential == null ||
                        salt == null ||
                        iterations == null ||
                        outputBytes == null ||
                        iterations < 1000 ||
                        outputBytes <= 0
                    ) {
                        result.error("INVALID_KDF_ARGUMENTS", "Invalid administrator KDF arguments.", null)
                    } else {
                        securityExecutor.execute {
                            val password = credential.toCharArray()
                            val spec = PBEKeySpec(password, salt, iterations, outputBytes * 8)
                            try {
                                val factory = SecretKeyFactory.getInstance("PBKDF2WithHmacSHA256")
                                val verifier = factory.generateSecret(spec).encoded
                                runOnUiThread {
                                    try {
                                        result.success(verifier)
                                    } finally {
                                        verifier.fill(0)
                                    }
                                }
                            } catch (_: GeneralSecurityException) {
                                runOnUiThread {
                                    result.error(
                                        "KDF_FAILED",
                                        "Administrator credential derivation failed.",
                                        null,
                                    )
                                }
                            } finally {
                                spec.clearPassword()
                                password.fill('\u0000')
                                salt.fill(0)
                            }
                        }
                    }
                }

                else -> result.notImplemented()
            }
        }
    }

    override fun onDestroy() {
        buzzerTonePlayer.stopAll()
        securityExecutor.shutdownNow()
        super.onDestroy()
    }

    companion object {
        init {
            System.loadLibrary("facerec")
        }

        private const val BUZZER_CHANNEL = "rev_crane_control_ops/buzzer"
        private const val FACE_SDK_CHANNEL = "samples.flutter.dev/facesdk"
        private const val SECURITY_CHANNEL = "rev_crane_control_ops/security"
        private const val DEFAULT_BUZZER_ID = "default"
    }
}

private class BuzzerTonePlayer {
    private val lock = Any()
    private val requests = LinkedHashMap<String, BuzzerRequest>()
    private var sequence = 0L
    private var generation = 0
    private var selectedPattern: BuzzerPattern? = null
    private var worker: Thread? = null

    fun start(id: String, patternName: String, priorityName: String) {
        synchronized(lock) {
            sequence += 1
            requests[id] = BuzzerRequest(
                pattern = BuzzerPattern.fromName(patternName),
                priority = priorityValue(priorityName),
                sequence = sequence,
            )

            val nextPattern = selectedRequestLocked()?.pattern
            if (nextPattern == selectedPattern && worker?.isAlive == true) {
                return
            }
            restartLocked(nextPattern)
        }
    }

    fun stop(id: String) {
        synchronized(lock) {
            if (requests.remove(id) == null) return
            val nextPattern = selectedRequestLocked()?.pattern
            if (nextPattern == selectedPattern && worker?.isAlive == true) {
                return
            }
            restartLocked(nextPattern)
        }
    }

    fun stopAll() {
        synchronized(lock) {
            requests.clear()
            restartLocked(null)
        }
    }

    private fun selectedRequestLocked(): BuzzerRequest? {
        return requests.values.maxWithOrNull(
            compareBy<BuzzerRequest> { it.priority }.thenBy { it.sequence },
        )
    }

    private fun restartLocked(nextPattern: BuzzerPattern?) {
        generation += 1
        selectedPattern = nextPattern
        worker?.interrupt()
        worker = null

        if (nextPattern != null) {
            val playbackGeneration = generation
            worker = thread(
                start = true,
                isDaemon = true,
                name = "rev-crane-buzzer",
            ) {
                playTone(nextPattern, playbackGeneration)
            }
        }
    }

    private fun isCurrent(playbackGeneration: Int): Boolean {
        return synchronized(lock) {
            playbackGeneration == generation && selectedPattern != null
        }
    }

    private fun playTone(pattern: BuzzerPattern, playbackGeneration: Int) {
        val sampleRate = 44100
        val bufferFrames = 1024
        val channelConfig = AudioFormat.CHANNEL_OUT_MONO
        val encoding = AudioFormat.ENCODING_PCM_16BIT
        val minBufferBytes = AudioTrack.getMinBufferSize(
            sampleRate,
            channelConfig,
            encoding,
        )
        val bufferSizeBytes = maxOf(minBufferBytes, bufferFrames * 2 * 4)
        val samples = ShortArray(bufferFrames)

        @Suppress("DEPRECATION")
        val track = AudioTrack(
            AudioManager.STREAM_MUSIC,
            sampleRate,
            channelConfig,
            encoding,
            bufferSizeBytes,
            AudioTrack.MODE_STREAM,
        )

        try {
            if (track.state != AudioTrack.STATE_INITIALIZED) return

            track.play()
            var sampleIndex = 0L
            var carrierPhase = 0.0
            var harmonicPhase = 0.0
            var wobblePhase = 0.0
            val twoPi = 2.0 * PI
            val carrierStep = twoPi * pattern.frequencyHz / sampleRate
            val harmonicStep = twoPi * pattern.frequencyHz * 2.03 / sampleRate
            val wobbleStep = twoPi * 5.0 / sampleRate

            while (isCurrent(playbackGeneration)) {
                for (i in samples.indices) {
                    val envelope = pattern.envelope(sampleIndex, sampleRate)
                    val tone = if (envelope > 0.0) {
                        val body = sin(carrierPhase) + 0.35 * sin(harmonicPhase)
                        val wobble = 0.82 + 0.18 * sin(wobblePhase)
                        body / 1.35 * wobble * envelope * 0.38
                    } else {
                        0.0
                    }

                    samples[i] = (tone * Short.MAX_VALUE.toDouble())
                        .toInt()
                        .coerceIn(Short.MIN_VALUE.toInt(), Short.MAX_VALUE.toInt())
                        .toShort()

                    carrierPhase = advancePhase(carrierPhase, carrierStep, twoPi)
                    harmonicPhase = advancePhase(harmonicPhase, harmonicStep, twoPi)
                    wobblePhase = advancePhase(wobblePhase, wobbleStep, twoPi)
                    sampleIndex += 1
                }

                val written = track.write(samples, 0, samples.size)
                if (written < 0) break
            }
        } catch (_: Throwable) {
        } finally {
            try {
                track.stop()
            } catch (_: Throwable) {
            }
            track.release()
        }
    }

    private fun advancePhase(phase: Double, step: Double, twoPi: Double): Double {
        val next = phase + step
        return if (next >= twoPi) next - twoPi else next
    }

    private fun priorityValue(name: String): Int {
        return when (name) {
            "high" -> 2
            "normal" -> 1
            else -> 0
        }
    }
}

private data class BuzzerRequest(
    val pattern: BuzzerPattern,
    val priority: Int,
    val sequence: Long,
)

private data class OnWindow(
    val startMs: Int,
    val endMs: Int,
)

private data class BuzzerPattern(
    val frequencyHz: Double,
    val cycleMs: Int,
    val onWindows: List<OnWindow>,
) {
    fun envelope(sampleIndex: Long, sampleRate: Int): Double {
        if (onWindows.isEmpty()) return 1.0

        val cycleSamples = cycleMs.toLong() * sampleRate / 1000L
        if (cycleSamples <= 0L) return 0.0

        val position = sampleIndex % cycleSamples
        val fadeSamples = maxOf(1L, 12L * sampleRate / 1000L)

        for (window in onWindows) {
            val start = window.startMs.toLong() * sampleRate / 1000L
            val end = window.endMs.toLong() * sampleRate / 1000L
            if (position >= start && position < end) {
                val fadeIn = (position - start).toDouble() / fadeSamples
                val fadeOut = (end - position).toDouble() / fadeSamples
                return min(fadeIn.coerceIn(0.0, 1.0), fadeOut.coerceIn(0.0, 1.0))
            }
        }

        return 0.0
    }

    companion object {
        fun fromName(name: String): BuzzerPattern {
            return when (name) {
                "pulsing" -> BuzzerPattern(
                    frequencyHz = 740.0,
                    cycleMs = 820,
                    onWindows = listOf(OnWindow(0, 460)),
                )

                "doubleBeep" -> BuzzerPattern(
                    frequencyHz = 900.0,
                    cycleMs = 980,
                    onWindows = listOf(OnWindow(0, 140), OnWindow(230, 370)),
                )

                else -> BuzzerPattern(
                    frequencyHz = 820.0,
                    cycleMs = 1000,
                    onWindows = emptyList(),
                )
            }
        }
    }
}
