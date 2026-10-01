package com.fluttering13.terpsichore

import android.content.Context
import android.graphics.Bitmap
import android.media.MediaMetadataRetriever
import android.os.Handler
import android.os.Looper
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.util.UUID
import java.util.concurrent.Executors
import java.util.concurrent.locks.ReentrantReadWriteLock
import kotlin.concurrent.read
import kotlin.concurrent.write
import kotlin.math.max

/** Independent A/B workers; each video is sampled in chronological order. */
class Pose3dPlugin : FlutterPlugin, MethodChannel.MethodCallHandler {
    private lateinit var context: Context
    private lateinit var channel: MethodChannel
    private val worker = Executors.newFixedThreadPool(2)
    private val lifecycle = ReentrantReadWriteLock(true)
    private val limiter = Pose3dFrameLimiter()
    private var plan: Pose3dPlan? = null
    private var plannedModel: String? = null
    private val main = Handler(Looper.getMainLooper())
    private val sessions = mutableMapOf<String, Session>()
    @Volatile private var attached = false

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        context = binding.applicationContext
        channel = MethodChannel(binding.binaryMessenger, "terpsichore/pose3d")
        attached = true
        channel.setMethodCallHandler(this)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        if (call.method !in listOf("configure", "create", "frame", "close")) {
            result.notImplemented(); return
        }
        worker.execute {
            try {
                check(attached) { "3D engine detached" }
                val value: Any? = when (call.method) {
                    "configure" -> lifecycle.write {
                        check(sessions.isEmpty()) { "Another 3D analysis is running" }
                        val model = requireNotNull(call.argument<String>("model"))
                        val hardware = Pose3dPerformance.read(context)
                        val selected = Pose3dPerformance.plan(hardware,model)
                        plan=selected;plannedModel=model
                        selected.toMap(hardware)
                    }
                    "create" -> lifecycle.write {
                        val id = UUID.randomUUID().toString()
                        val path = requireNotNull(call.argument<String>("path"))
                        val model = requireNotNull(call.argument<String>("model"))
                        val selected=plan ?: Pose3dPerformance.plan(Pose3dPerformance.read(context),model)
                        check(plannedModel == null || plannedModel == model) { "Model does not match analysis plan" }
                        if(sessions.size>=selected.workers) throw CapacityException()
                        if(sessions.isNotEmpty()) {
                            val h=Pose3dPerformance.read(context)
                            if(h.lowMemory || h.thermalStatus>=2 || h.availableBytes<selected.reserveBytes+selected.bytesPerWorker)
                                throw CapacityException()
                        }
                        sessions[id] = Session(context, path, model,selected.modelThreads)
                        id
                    }
                    "frame" -> lifecycle.read {
                        val session = requireNotNull(sessions[call.argument<String>("id")]) { "3D session closed" }
                        limiter.run({
                            val h=Pose3dPerformance.read(context)
                            if(h.lowMemory || h.thermalStatus>=2 || h.availableBytes<(plan?.reserveBytes ?: 0)) 1
                            else plan?.workers ?: 1
                        }) {
                            synchronized(session) { session.frame(requireNotNull(call.argument<Number>("timeUs")).toLong()) }
                        }
                    }
                    else -> lifecycle.write { sessions.remove(call.argument<String>("id"))?.close(); null }
                }
                main.post { result.success(value) }
            } catch (e: Exception) {
                main.post { result.error(if(e is CapacityException) "POSE3D_CAPACITY" else "POSE3D_FAILED", e.message ?: e.javaClass.simpleName, null) }
            }
        }
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        attached = false
        channel.setMethodCallHandler(null)
        worker.execute { lifecycle.write { sessions.values.forEach { it.close() }; sessions.clear() } }
        worker.shutdown()
    }

    private class CapacityException : IllegalStateException("3D worker capacity changed")

    internal class Session(context: Context, path: String, model: String, modelThreads: Int = 4) : AutoCloseable {
        private val retriever = MediaMetadataRetriever()
        private var nlf: NlfPose3d? = null
        init {
            try {
                require(model == "nlf-int8") { "Unknown 3D model" }
                retriever.setDataSource(path)
                nlf = NlfPose3d(context,modelThreads)
            } catch (e: Exception) { close(); throw e }
        }

        fun frame(timeUs: Long): List<Double>? {
            require(timeUs >= 0)
            val original = retriever.getFrameAtTime(timeUs, MediaMetadataRetriever.OPTION_CLOSEST)
                ?: throw IllegalStateException("Cannot decode video frame at $timeUs us")
            val ratio = minOf(1.0, 1280.0 / max(original.width, original.height))
            val scaled = if (ratio < 1) Bitmap.createScaledBitmap(original,
                max(1, (original.width * ratio).toInt()), max(1, (original.height * ratio).toInt()), true) else original
            // Normalize the decoded bitmap format before ML Kit and NLF read pixels.
            val bitmap = if (scaled.config == Bitmap.Config.ARGB_8888) scaled
                else checkNotNull(scaled.copy(Bitmap.Config.ARGB_8888, false)) { "Cannot convert video frame" }
            try {
                return nlf!!.infer(bitmap)
            } finally {
                if (bitmap !== scaled) bitmap.recycle()
                if (scaled !== original) scaled.recycle()
                original.recycle()
            }
        }
        override fun close() {
            try { nlf?.close() } finally { retriever.release() }
        }
    }
}
