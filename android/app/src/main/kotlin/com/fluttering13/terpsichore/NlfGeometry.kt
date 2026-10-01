package com.fluttering13.terpsichore

import kotlin.math.*

/** Camera math for NLF-L 0.3.2, in metres. Kept independent of Android for fixture tests. */
internal object NlfGeometry {
    data class Crop(val rotation: Array<DoubleArray>, val focal: Double, val scale: Double)
    data class LinearImage(val width: Int, val height: Int, val rgb: FloatArray)
    fun pyramid(pixels: IntArray, width: Int, height: Int): List<LinearImage> {
        val lut = FloatArray(256) { (it/255.0).pow(2.2).toFloat() }
        val levels = mutableListOf(LinearImage(width,height,FloatArray(width*height*3) {
            lut[(pixels[it/3] shr (16-8*(it%3))) and 255]
        }))
        repeat(2) {
            val prev=levels.last(); val w=prev.width/2;val h=prev.height/2
            levels.add(LinearImage(w,h,FloatArray(w*h*3) { i ->
                val x=(i/3)%w*2;val y=(i/3)/w*2;val c=i%3
                (prev.rgb[(y*prev.width+x)*3+c]+prev.rgb[(y*prev.width+x+1)*3+c]+
                    prev.rgb[((y+1)*prev.width+x)*3+c]+prev.rgb[((y+1)*prev.width+x+1)*3+c])*.25f
            }))
        }
        return levels
    }
    fun warp(levels: List<LinearImage>, crop: Crop, gamma: Double): FloatArray {
        val level = floor(-log2(crop.scale)).toInt().coerceIn(0,2)
        val image = levels[level];val scale = 1.0/(1 shl level)
        val original = levels[0]; val f=focal(original.width,original.height)*scale
        // corner_aligned_scale_mat: x' = s*x + (s-1)/2.
        val cx=(original.width-1)/2.0*scale+(scale-1)/2
        val cy=(original.height-1)/2.0*scale+(scale-1)/2
        fun pixel(x: Int,y: Int,c: Int): Double = if(x<0 || y<0 || x>=image.width || y>=image.height) 0.0
            else image.rgb[(y*image.width+x)*3+c].toDouble()
        val output=FloatArray(3*384*384)
        for(y in 0 until 384) for(x in 0 until 384) {
            val ray=unrotate(crop.rotation,doubleArrayOf((x-192)/crop.focal,(y-192)/crop.focal,1.0))
            if(ray[2]<=1e-6) continue
            val sx=f*ray[0]/ray[2]+cx;val sy=f*ray[1]/ray[2]+cy
            val ix=floor(sx).toInt();val iy=floor(sy).toInt();val dx=sx-ix;val dy=sy-iy
            for(c in 0..2) {
                val value=(pixel(ix,iy,c)*(1-dx)+pixel(ix+1,iy,c)*dx)*(1-dy)+
                    (pixel(ix,iy+1,c)*(1-dx)+pixel(ix+1,iy+1,c)*dx)*dy
                output[c*384*384+y*384+x]=value.coerceIn(0.0,1.0).pow(gamma/2.2).toFloat()
            }
        }
        return output
    }
    fun dot(a: DoubleArray, b: DoubleArray) = a.indices.sumOf { a[it] * b[it] }
    private fun unit(a: DoubleArray): DoubleArray { val n = sqrt(dot(a, a)); return DoubleArray(3) { a[it] / n } }
    private fun cross(a: DoubleArray, b: DoubleArray) = doubleArrayOf(a[1]*b[2]-a[2]*b[1], a[2]*b[0]-a[0]*b[2], a[0]*b[1]-a[1]*b[0])
    fun transform(r: Array<DoubleArray>, v: DoubleArray) = DoubleArray(3) { dot(r[it], v) }
    fun unrotate(r: Array<DoubleArray>, v: DoubleArray) = DoubleArray(3) { j -> (0..2).sumOf { i -> r[i][j]*v[i] } }
    fun focal(width: Int, height: Int) = max(width, height)/(2*tan(Math.toRadians(55.0)/2))
    fun crop(width: Int, height: Int, box: DoubleArray, aug: Int): Crop {
        val f = focal(width, height); val cx = (width-1)/2.0; val cy = (height-1)/2.0
        val x = box[0]; val y = box[1]; val w = box[2]; val h = box[3]
        fun ray(px: Double, py: Double) = doubleArrayOf((px-cx)/f, (py-cy)/f, 1.0)
        val z = unit(ray(x+w/2, y+h/2)); val xx = unit(cross(z, doubleArrayOf(0.0,-1.0,0.0)))
        val base = arrayOf(xx, cross(z,xx), z)
        fun project(px: Double, py: Double): DoubleArray {
            val v = transform(base, ray(px,py)); return doubleArrayOf(f*v[0]/v[2]+cx, f*v[1]/v[2]+cy)
        }
        fun distance(a: DoubleArray, b: DoubleArray) = hypot(a[0]-b[0], a[1]-b[1])
        val size = max(distance(project(x+w/2,y), project(x+w/2,y+h)), distance(project(x,y+h/2), project(x+w,y+h/2)))
        val scale = 384.0/max(size, 1.0)*doubleArrayOf(.8,.9,1.0,1.05,1.1)[aug]
        val angle = -Math.toRadians(-25.0+12.5*aug)
        val flip = if (aug % 2 == 1) -1.0 else 1.0
        val r = arrayOf(DoubleArray(3) { flip*(cos(angle)*base[0][it]-sin(angle)*base[1][it]) },
            DoubleArray(3) { sin(angle)*base[0][it]+cos(angle)*base[1][it] }, base[2])
        return Crop(r,f*scale,scale)
    }

    private fun inFov(x: Double, y: Double, factor: Double) =
        x >= 32*factor && y >= 32*factor && x <= 384-32*factor && y <= 384-32*factor

    fun reconstruct(c2: FloatArray, c3: FloatArray, uncertainty: FloatArray, focal: Double): Array<DoubleArray> {
        val xy = Array(17) { j -> doubleArrayOf((c2[j*2]-192)/focal,(c2[j*2+1]-192)/focal) }
        val b = Array(17) { j -> DoubleArray(2) { k -> xy[j][k]*c3[j*3+2]-c3[j*3+k] } }
        val valid = BooleanArray(17) { uncertainty[it]<.3 && inFov(c2[it*2].toDouble(),c2[it*2+1].toDouble(),1.0) }
        val count = max(1, valid.count { it } * 2)
        fun rms(v: Array<DoubleArray>) = sqrt((0..16).filter { valid[it] }.sumOf { dot(v[it],v[it]) }/count+1e-10)
        val s2 = rms(xy); val sb = rms(b)
        val ata = Array(3) { i -> DoubleArray(3) { j -> if (i==j) 1e-4 else 0.0 } }
        val atb = DoubleArray(3)
        for (j in 0..16) for (k in 0..1) {
            val a = doubleArrayOf(if(k==0) 1.0 else 0.0, if(k==1) 1.0 else 0.0, -xy[j][k]/s2)
            val weight = if(valid[j]) 1.0+1e-8 else 1e-8
            for (u in 0..2) {
                atb[u] += a[u]*b[j][k]/sb*weight
                for(v in 0..2) ata[u][v] += a[u]*a[v]*weight
            }
        }
        // Cholesky solve of the regularized symmetric positive-definite 3x3 system.
        val l = Array(3) { DoubleArray(3) }
        for(i in 0..2) for(j in 0..i) {
            val s = ata[i][j]-(0 until j).sumOf { l[i][it]*l[j][it] }
            l[i][j] = if(i==j) sqrt(max(s,1e-20)) else s/l[j][j]
        }
        val v = DoubleArray(3)
        for(i in 0..2) v[i] = (atb[i]-(0 until i).sumOf { l[i][it]*v[it] })/l[i][i]
        val ref = DoubleArray(3)
        for(i in 2 downTo 0) ref[i] = (v[i]-(i+1..2).sumOf { l[it][i]*ref[it] })/l[i][i]
        ref[0]*=sb; ref[1]*=sb; ref[2]*=sb/s2
        return Array(17) { j ->
            val p = DoubleArray(3) { c3[j*3+it]+ref[it] }
            val depth = max(.1,p[2])
            val px = (focal*p[0]+192*p[2])/depth; val py = (focal*p[1]+192*p[2])/depth
            if(p[2]>.001 && inFov(px,py,.6)) {
                p[0] = (p[0]+xy[j][0]*p[2])*.5
                p[1] = (p[1]+xy[j][1]*p[2])*.5
            }
            p
        }
    }

    fun fuse(poses: List<Array<DoubleArray>>, uncertainties: List<FloatArray>): List<Double> {
        require(poses.size == 5 && uncertainties.size == 5)
        val squares = poses.map { p -> p.sumOf { dot(it,it) }/51 }
        val meanScale = squares.average()
        val scaled = poses.mapIndexed { a,p -> val s = sqrt(meanScale/max(squares[a],1e-12)); p.map { v -> DoubleArray(3) { v[it]*s } } }
        val output = Array(17) { DoubleArray(3) }
        val confidence = DoubleArray(17)
        for(j in 0..16) {
            val original = DoubleArray(5) { max(uncertainties[it][j].toDouble(),1e-6).pow(-1.5) }
            var weights = original.copyOf()
            fun average() = DoubleArray(3) { k -> (0..4).sumOf { a -> scaled[a][j][k]*weights[a] }/weights.sum() }
            var center = average()
            repeat(10) {
                weights = DoubleArray(5) { a ->
                    val distance = sqrt((0..2).sumOf { (scaled[a][j][it]-center[it]).pow(2) })
                    original[a]/(distance+.05)
                }
                center = average()
            }
            output[j] = center
            val uncertainty = (0..4).sumOf { uncertainties[it][j]*weights[it] }/weights.sum()
            confidence[j] = (1.0-uncertainty).coerceIn(0.0,1.0)
        }
        return (0..16).flatMap { j -> listOf(output[j][0],-output[j][1],output[j][2],confidence[j]) }
    }
}
