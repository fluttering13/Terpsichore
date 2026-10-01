package com.fluttering13.terpsichore

import ai.onnxruntime.OnnxTensor
import ai.onnxruntime.OrtEnvironment
import ai.onnxruntime.OrtSession
import android.content.Context
import android.graphics.Bitmap
import com.google.android.gms.tasks.Tasks
import com.google.mlkit.vision.common.InputImage
import com.google.mlkit.vision.pose.PoseDetection
import com.google.mlkit.vision.pose.accurate.AccuratePoseDetectorOptions
import java.io.File
import java.nio.FloatBuffer
import kotlin.math.*

/** Fixed H36M-17 QDQ INT8 core, five original NLF augmentations, perspective reconstruction. */
internal class NlfPose3d(context: Context, modelThreads: Int = 4) : AutoCloseable {
    companion object { private val modelFileLock = Any() }
    private val env = OrtEnvironment.getEnvironment()
    private val session: OrtSession
    private val detector = PoseDetection.getClient(AccuratePoseDetectorOptions.Builder()
        // Independent video streams must not share ML Kit's temporal tracking state.
        // Image mode makes the person box depend only on the current source frame.
        .setDetectorMode(AccuratePoseDetectorOptions.SINGLE_IMAGE_MODE).build())
    init {
        try {
            // ORT's path loader avoids a second full 126 MB Java byte array.
            val directory = File(context.noBackupFilesDir,"pose3d").apply { mkdirs() }
            val model = File(directory,"nlf-l-int8-v1.onnx")
            val expected = 126298385L
            synchronized(modelFileLock) { if (!model.exists() || model.length()!=expected) {
                val pending = File(directory,"nlf-l-int8-v1.pending")
                try {
                    context.assets.open("pose3d/nlf-l-int8.onnx").use { input -> pending.outputStream().use { input.copyTo(it) } }
                    check(pending.length()==expected) { "Incomplete NLF model" }
                    check(pending.renameTo(model)) { "Cannot prepare NLF model" }
                } finally { pending.delete() }
            } }
            session = OrtSession.SessionOptions().use { options ->
                options.setIntraOpNumThreads(modelThreads.coerceIn(1,4)); options.setInterOpNumThreads(1)
                // Idle workers must not spin while the other clip decodes/warps a frame.
                options.addConfigEntry("session.intra_op.allow_spinning", "0")
                env.createSession(model.absolutePath,options)
            }
        } catch(e: Exception) { detector.close(); throw e }
    }

    fun infer(bitmap: Bitmap): List<Double>? {
        // ML Kit is only the 2D person-box tracker here; all 3D coordinates come from NLF.
        val landmarks = Tasks.await(detector.process(InputImage.fromBitmap(bitmap,0))).allPoseLandmarks
            .filter { it.inFrameLikelihood>=.35f }
        if(landmarks.size<8) return null
        val x0=landmarks.minOf { it.position.x }.toDouble(); val x1=landmarks.maxOf { it.position.x }.toDouble()
        val y0=landmarks.minOf { it.position.y }.toDouble(); val y1=landmarks.maxOf { it.position.y }.toDouble()
        val w=(x1-x0)*1.2; val h=(y1-y0)*1.2
        if(w<16 || h<16) return null
        val box=doubleArrayOf((x0+x1-w)/2,(y0+y1-h)/2,w,h)
        val pixels=IntArray(bitmap.width*bitmap.height)
        bitmap.getPixels(pixels,0,bitmap.width,0,0,bitmap.width,bitmap.height)
        val pyramid=NlfGeometry.pyramid(pixels,bitmap.width,bitmap.height)
        val poses=mutableListOf<Array<DoubleArray>>()
        val uncertainties=mutableListOf<FloatArray>()
        for(aug in 0..4) {
            val crop=NlfGeometry.crop(bitmap.width,bitmap.height,box,aug)
            val data=NlfGeometry.warp(pyramid,crop,.6+.1*aug)
            OnnxTensor.createTensor(env,FloatBuffer.wrap(data),longArrayOf(1,3,384,384)).use { tensor ->
                val suffix=if(aug%2==1) "_flipped" else ""
                val names=setOf("coords2d$suffix","coords3d$suffix","uncertainty$suffix")
                session.run(mapOf("image" to tensor),names).use { result ->
                    fun floats(name: String): FloatArray {
                        val buffer=(result.get(name+suffix).get() as OnnxTensor).floatBuffer
                        return FloatArray(buffer.remaining()).also { buffer.get(it) }
                    }
                    val c2=floats("coords2d");val c3=floats("coords3d");val u=floats("uncertainty")
                    if((c2.asSequence()+c3.asSequence()+u.asSequence()).any { !it.isFinite() }) return null
                    poses.add(NlfGeometry.reconstruct(c2,c3,u,crop.focal).map { NlfGeometry.unrotate(crop.rotation,it) }.toTypedArray())
                    uncertainties.add(FloatArray(17) { u[it]*3 })
                }
            }
        }
        return NlfGeometry.fuse(poses,uncertainties).takeIf { it.all { v -> v.isFinite() } }
    }

    override fun close() { try { detector.close() } finally { session.close() } }
}
