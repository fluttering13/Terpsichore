package com.fluttering13.terpsichore

import org.junit.Assert.*
import org.junit.Test

class Pose3dPerformanceTest {
    @Test fun frameLimiterReleasesCapacityWhenInferenceFails() {
        val limiter = Pose3dFrameLimiter()
        val executor = java.util.concurrent.Executors.newSingleThreadExecutor()
        try {
            try {
                limiter.run({ 1 }) { throw IllegalStateException("inference failed") }
                fail("Expected inference failure")
            } catch (_: IllegalStateException) { }
            val next = executor.submit<Int> { limiter.run({ 1 }) { 42 } }
            assertEquals(42, next.get(2, java.util.concurrent.TimeUnit.SECONDS).toInt())
        } finally { executor.shutdownNow() }
    }
    private val mib=Pose3dPerformance.MIB
    private val flagship=Pose3dHardware(8,5,11000*mib,4400*mib,false,256*mib,512*mib,0)
    @Test fun flagshipAllocatesTwoWorkersWithinCpuAndMemoryBudget() {
        val p=Pose3dPerformance.plan(flagship,"nlf-int8")
        assertEquals(2,p.workers);assertEquals(2,p.modelThreads)
        assertTrue(p.reserveBytes+2*p.bytesPerWorker<=flagship.availableBytes)
    }
    @Test fun memoryPressureHeatOrSmallCpuKeepSingleWorker() {
        for(h in listOf(flagship.copy(availableBytes=1800*mib),flagship.copy(lowMemory=true),
            flagship.copy(thermalStatus=2),flagship.copy(cores=4),flagship.copy(heapBytes=256*mib))) {
            assertEquals(1,Pose3dPerformance.plan(h,"nlf-int8").workers)
        }
    }
}
