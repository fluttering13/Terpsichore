package com.fluttering13.terpsichore

import android.util.Log
import androidx.test.platform.app.InstrumentationRegistry
import java.io.File
import org.junit.Assert.*
import org.junit.Test

/** Local A/B airflare fixtures are deliberately not committed. See docs/pose3d.md. */
class Pose3dDeviceTest {
    @Test fun nlfInt8ReconstructsBothAirflareClips() = checkModel("nlf-int8")
    private fun checkModel(model: String) {
        val instrumentation = InstrumentationRegistry.getInstrumentation()
        org.junit.Assume.assumeTrue("Local A/B video fixtures are required",
            instrumentation.context.assets.list("pose3d")?.toSet()?.containsAll(listOf("A.mp4", "B.mp4")) == true)
        val context = instrumentation.targetContext
        for(side in listOf("A","B")) {
            val input=File(context.cacheDir,"pose3d-test-$side.mp4")
            try {
                instrumentation.context.assets.open("pose3d/$side.mp4").use { src -> input.outputStream().use { src.copyTo(it) } }
                val started=System.nanoTime()
                Pose3dPlugin.Session(context,input.absolutePath,model).use { session ->
                    val times=if(side=="A") listOf(0L,600000L,1100000L) else listOf(0L,1500000L,3000000L)
                    var detected=0
                    for(t in times) {
                        val before=System.nanoTime()
                        val pose=session.frame(t)
                        Log.i("Pose3dTest","$model $side $t us: ${(System.nanoTime()-before)/1e6} ms, detected=${pose!=null}")
                        if(pose!=null) {
                            detected++
                            assertEquals(68,pose.size)
                            assertTrue(pose.all { it.isFinite() })
                            val span=(0..16).maxOf { j -> kotlin.math.sqrt((0..2).sumOf { k -> (pose[j*4+k]-pose[k]).let { it*it } }) }
                            assertTrue("Nondegenerate skeleton: $span",span>.15 && span<4)
                        }
                    }
                    assertTrue("$model must reconstruct $side",detected>=2)
                }
                Log.i("Pose3dTest","$model $side total ${(System.nanoTime()-started)/1e9} s")
            } finally { input.delete() }
        }
    }
}
