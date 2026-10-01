package com.fluttering13.terpsichore

import android.os.Debug
import androidx.test.platform.app.InstrumentationRegistry
import java.io.File
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicBoolean
import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test

class Pose3dPerformanceDeviceTest {
    @Test fun compareWorkerBudgetsOnBothClips() {
        val instrumentation=InstrumentationRegistry.getInstrumentation()
        org.junit.Assume.assumeTrue("Local A/B video fixtures are required",
            instrumentation.context.assets.list("pose3d")?.toSet()?.containsAll(listOf("A.mp4", "B.mp4")) == true)
        val context=instrumentation.targetContext
        val files=listOf("A","B").map { side ->
            File(context.cacheDir,"pose3d-perf-$side.mp4").also { target ->
                instrumentation.context.assets.open("pose3d/$side.mp4").use { src -> target.outputStream().use { src.copyTo(it) } }
            }
        }
        val rows=JSONArray()
        val hardware=Pose3dPerformance.read(context)
        val report=JSONObject().put("hardware",JSONObject(Pose3dPerformance.plan(hardware,"nlf-int8").toMap(hardware))).put("runs",rows)
        val output=File(context.filesDir,"pose3d-performance.json")
        val executor=Executors.newFixedThreadPool(2)
        val reference=mutableMapOf<String,List<Double>?>()
        try {
            for(round in 0..1) for((workers,threads) in (if(round==0) listOf(1 to 4,2 to 2,2 to 3) else listOf(2 to 3,2 to 2,1 to 4))) {
                var peak=Debug.getPss(); val monitoring=AtomicBoolean(true)
                val monitor=Thread { while(monitoring.get()) { peak=maxOf(peak,Debug.getPss());Thread.sleep(200) } }.apply { start() }
                val start=System.nanoTime();val before=Pose3dPerformance.read(context)
                fun run(side: Int): List<List<Double>?> = Pose3dPlugin.Session(context,files[side].absolutePath,"nlf-int8",threads).use { model ->
                    (0..3).map { i -> model.frame(i*(if(side==0) 250000L else 500000L)) }
                }
                val results=try {
                    if(workers==1) listOf(run(0),run(1)) else {
                        val a=executor.submit<List<List<Double>?>> { run(0) };val b=executor.submit<List<List<Double>?>> { run(1) }
                        listOf(a.get(),b.get())
                    }
                } finally { monitoring.set(false);monitor.join() }
                val seconds=(System.nanoTime()-start)/1e9
                var maxDelta=0.0;var detected=0
                for(side in 0..1) for(i in 0..3) {
                    val pose=results[side][i];val key="$side-$i"
                    if(round==0 && workers==1) reference[key]=pose
                    assertEquals("Detection must not change $key",reference[key]!=null,pose!=null)
                    if(pose!=null) {
                        detected++
                        for(j in pose.indices) maxDelta=maxOf(maxDelta,kotlin.math.abs(pose[j]-reference[key]!![j]))
                    }
                }
                assertTrue("Parallel output changed: $maxDelta",maxDelta<.001)
                assertTrue("Non-finite output", results.flatten().filterNotNull().flatten().all { it.isFinite() })
                rows.put(JSONObject().put("round",round).put("workers",workers).put("threads",threads)
                    .put("seconds",seconds).put("peakPssMiB",peak/1024.0).put("detected",detected).put("maxDelta",maxDelta)
                    .put("thermalBefore",before.thermalStatus).put("thermalAfter",Pose3dPerformance.read(context).thermalStatus))
                output.writeText(report.toString(2))
            }
        } finally { executor.shutdown();files.forEach { it.delete() } }
    }
}
