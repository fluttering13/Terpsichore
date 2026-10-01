package com.fluttering13.terpsichore

import java.io.DataInputStream
import org.junit.Assert.*
import org.junit.Test

class NlfGeometryTest {
    private fun fixture(name: String) = DataInputStream(javaClass.getResourceAsStream("/pose3d/$name.bin")!!)
    @Test fun perspectiveMatchesOriginalTorchScriptOnRealVideoPredictions() {
        for(name in listOf("A-000","B-030")) fixture(name).use { input ->
            val c2=FloatArray(34) { input.readFloat() };val c3=FloatArray(51) { input.readFloat() }
            val u=FloatArray(17) { input.readFloat() };val f=input.readFloat().toDouble()
            val expected=FloatArray(51) { input.readFloat() }
            val actual=NlfGeometry.reconstruct(c2,c3,u,f).flatMap { it.toList() }
            actual.forEachIndexed { i,v -> assertEquals("$name coordinate $i",expected[i].toDouble(),v,0.0001) }
        }
    }
    @Test fun fiveCropRotationsAndLinearRgbPyramidMatchOriginalIncludingFlipAndPadding() {
        val w=801;val h=601
        val pixels=IntArray(w*h) { i -> val x=i%w;val y=i/w
            (255 shl 24) or (((x*3+y)%256) shl 16) or (((x+y*2)%256) shl 8) or ((x*7+y*5)%256)
        }
        val pyramid=NlfGeometry.pyramid(pixels,w,h)
        for(name in listOf("crop-0","crop-1")) fixture(name).use { input ->
            val box=DoubleArray(4) { input.readFloat().toDouble() }
            val f=FloatArray(5) { input.readFloat() };val r=FloatArray(45) { input.readFloat() }
            val probes=FloatArray(200) { input.readFloat() }
            for(a in 0..4) {
                val crop=NlfGeometry.crop(w,h,box,a)
                assertEquals(f[a].toDouble(),crop.focal,0.001)
                for(i in 0..8) assertEquals(r[a*9+i].toDouble(),crop.rotation[i/3][i%3],0.000001)
                val image=NlfGeometry.warp(pyramid,crop,.6+.1*a)
                for(i in 0 until 40) {
                    val x=i*71%384;val y=i*113%384;val c=i%3
                    assertEquals("$name aug $a probe $i",probes[a*40+i].toDouble(),image[c*384*384+y*384+x].toDouble(),0.0005)
                }
            }
        }
    }
    @Test fun fusionPreservesIdenticalPosesAndConvertsToYUp() {
        val pose=Array(17) { doubleArrayOf(it*.01,it*.03,2.0) }
        val actual=NlfGeometry.fuse(List(5) { pose },List(5) { FloatArray(17) { .1f } })
        for(j in 0..16) {
            assertEquals(pose[j][0],actual[j*4],1e-10)
            assertEquals(-pose[j][1],actual[j*4+1],1e-10)
            assertEquals(pose[j][2],actual[j*4+2],1e-10)
        }
    }
}
