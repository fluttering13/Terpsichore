package com.example.terpsichore

import android.graphics.Bitmap
import com.google.android.gms.tasks.Tasks
import com.google.mlkit.vision.common.InputImage
import com.google.mlkit.vision.pose.PoseDetection
import com.google.mlkit.vision.pose.PoseDetector
import com.google.mlkit.vision.pose.accurate.AccuratePoseDetectorOptions
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodChannel
import java.util.UUID
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.Executors
import java.util.concurrent.locks.ReentrantReadWriteLock
import kotlin.concurrent.read
import kotlin.concurrent.write

/** One detector per video; independent A/B streams with benchmarked CPU policy. */
class AccuratePosePlugin : FlutterPlugin {
    private class Model(val detector: PoseDetector) {
        var closed = false
        fun close() { closed = true; detector.close() }
    }
    private val models = ConcurrentHashMap<String, Model>()
    private val pool = Executors.newFixedThreadPool(2)
    private val life = ReentrantReadWriteLock(true)
    private var detached = false
    private lateinit var channel: MethodChannel

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel = MethodChannel(binding.binaryMessenger, "terpsichore/mlkit_pose")
        channel.setMethodCallHandler { call, reply -> pool.execute {
            try { life.read {
                check(!detached)
                when (call.method) {
                    "create" -> {
                        val backend = call.argument<String>("backend")
                        require(backend == "mlkit-accurate" || backend == "mlkit-accurate-single")
                        val options = AccuratePoseDetectorOptions.Builder()
                            .setDetectorMode(if (backend == "mlkit-accurate-single")
                                AccuratePoseDetectorOptions.SINGLE_IMAGE_MODE else AccuratePoseDetectorOptions.STREAM_MODE)
                            .setPreferredHardwareConfigs(AccuratePoseDetectorOptions.CPU).build()
                        val id = UUID.randomUUID().toString()
                        models[id] = Model(PoseDetection.getClient(options))
                        reply.success(id)
                    }
                    "run" -> {
                        val model = models[call.argument<String>("id")] ?: error("Closed model")
                        synchronized(model) {
                            check(!model.closed)
                            val bgr = call.argument<ByteArray>("bgr") ?: error("Missing image")
                            require(bgr.size == 640 * 640 * 3)
                            val colors = IntArray(640 * 640) { i ->
                                (0xff shl 24) or ((bgr[i*3+2].toInt() and 255) shl 16) or
                                    ((bgr[i*3+1].toInt() and 255) shl 8) or (bgr[i*3].toInt() and 255)
                            }
                            val bitmap = Bitmap.createBitmap(colors, 640, 640, Bitmap.Config.ARGB_8888)
                            try {
                                val image = InputImage.fromBitmap(bitmap, 0)
                                val start = System.nanoTime()
                                val pose = Tasks.await(model.detector.process(image))
                                val end = System.nanoTime()
                                val output = ArrayList<Double>(51)
                                // Preserve the existing COCO17 overlay/alignment representation.
                                for (j in intArrayOf(0,2,5,7,8,11,12,13,14,15,16,23,24,25,26,27,28)) {
                                    val point = pose.getPoseLandmark(j)
                                    output.add((point?.position?.y ?: 0f).toDouble() / 640)
                                    output.add((point?.position?.x ?: 0f).toDouble() / 640)
                                    output.add((point?.inFrameLikelihood ?: 0f).toDouble())
                                }
                                reply.success(mapOf("points" to output, "start_ns" to start,
                                    "end_ns" to end, "peak_runs" to 0))
                            } finally { bitmap.recycle() }
                        }
                    }
                    "close" -> {
                        models.remove(call.argument<String>("id"))?.let { synchronized(it) { it.close() } }
                        reply.success(null)
                    }
                    else -> reply.notImplemented()
                }
            }} catch (e: Exception) { reply.error("POSE_ERROR", e.message, null) }
        }}
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
        life.write { detached = true; models.values.forEach { it.close() }; models.clear() }
        pool.shutdown()
    }
}
