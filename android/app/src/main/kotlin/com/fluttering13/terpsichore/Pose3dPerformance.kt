package com.fluttering13.terpsichore

import android.app.ActivityManager
import android.content.Context
import android.os.Build
import android.os.PowerManager
import java.io.File
import kotlin.math.max

internal data class Pose3dHardware(
    val cores: Int, val fastCores: Int, val totalBytes: Long, val availableBytes: Long,
    val lowMemory: Boolean, val memoryThreshold: Long, val heapBytes: Long,
    val thermalStatus: Int,
)

internal data class Pose3dPlan(val workers: Int, val modelThreads: Int, val reserveBytes: Long,
    val bytesPerWorker: Long, val reason: String) {
    fun toMap(h: Pose3dHardware) = mapOf(
        "workers" to workers, "modelThreads" to modelThreads, "cores" to h.cores,
        "fastCores" to h.fastCores, "totalBytes" to h.totalBytes, "availableBytes" to h.availableBytes,
        "heapBytes" to h.heapBytes, "thermalStatus" to h.thermalStatus, "reason" to reason,
        "reserveBytes" to reserveBytes, "bytesPerWorker" to bytesPerWorker)
}

/** Conservative admission estimates include model, activation tensors, decoder and crop buffers. */
internal object Pose3dPerformance {
    const val MIB = 1024L * 1024
    fun read(context: Context): Pose3dHardware {
        val am = context.getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager
        val info = ActivityManager.MemoryInfo().also(am::getMemoryInfo)
        val cores = Runtime.getRuntime().availableProcessors().coerceAtLeast(1)
        val frequencies = (0 until cores).mapNotNull { i ->
            runCatching { File("/sys/devices/system/cpu/cpu$i/cpufreq/cpuinfo_max_freq").readText().trim().toLong() }.getOrNull()
        }
        val fast = if (frequencies.size == cores && frequencies.max() > 0)
            frequencies.count { it >= frequencies.max() * .7 } else max(1, cores / 2)
        val thermal = if (Build.VERSION.SDK_INT >= 29)
            (context.getSystemService(Context.POWER_SERVICE) as PowerManager).currentThermalStatus else 0
        return Pose3dHardware(cores,fast,info.totalMem,info.availMem,info.lowMemory,info.threshold,
            Runtime.getRuntime().maxMemory(),thermal)
    }

    fun plan(h: Pose3dHardware, model: String): Pose3dPlan {
        require(model == "nlf-int8")
        val reserve = max(1024*MIB, h.memoryThreshold*2)
        val perWorker = 640*MIB
        val parallel = h.cores>=6 && h.fastCores>=4 && h.totalBytes>=6*1024*MIB &&
            h.availableBytes>=reserve+2*perWorker && h.heapBytes>=384*MIB && !h.lowMemory && h.thermalStatus<2
        val workers = if(parallel) 2 else 1
        val threads = (h.fastCores/workers).coerceIn(1,4)
        val reason = when {
            parallel -> "parallel-ab"
            h.lowMemory || h.availableBytes<reserve+2*perWorker || h.heapBytes<384*MIB -> "memory-budget"
            h.thermalStatus>=2 -> "thermal"
            else -> "cpu-budget"
        }
        return Pose3dPlan(workers,threads,reserve,perWorker,reason)
    }
}

/** Re-check pressure between frames. Already-running calls finish before reducing concurrency. */
internal class Pose3dFrameLimiter {
    private val monitor = Object()
    private var active = 0
    fun <T> run(limit: () -> Int, action: () -> T): T {
        synchronized(monitor) {
            while(active >= limit().coerceIn(1,2)) monitor.wait()
            active++
        }
        try { return action() }
        finally { synchronized(monitor) { active--;monitor.notifyAll() } }
    }
}
