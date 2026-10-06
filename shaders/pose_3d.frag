#version 460 core
#include <flutter/runtime_effect.glsl>

// View-space capsules. Each pixel keeps its nearest surface intersection,
// rather than sorting entire bones by their mean depth.
uniform vec2 uCenter;
uniform float uScale;
uniform vec3 uColor;
uniform vec3 uForward;
uniform vec4 uCapsules[72];
out vec4 fragColor;

float sphereHit(vec3 ray, vec3 center, float radius) {
  vec3 q = ray - center;
  float h = radius * radius - dot(q.xy, q.xy);
  if (h < 0.0) return 10000.0;
  return -q.z - sqrt(h);
}

void main() {
  vec2 pixel = FlutterFragCoord().xy;
  vec3 ray = vec3((pixel.x-uCenter.x)/uScale,
                  (uCenter.y-pixel.y)/uScale, -8.0);
  float closest = 10000.0;
  vec3 normal = vec3(0.0, 0.0, -1.0);
  for (int i = 0; i < 36; i++) {
    vec4 first = uCapsules[i*2];
    vec3 a = first.xyz;
    vec3 b = uCapsules[i*2+1].xyz;
    float radius = first.w;
    if (radius <= 0.0) continue;
    // Reject pixels outside the capsule's projected bounds before square roots.
    if (any(lessThan(ray.xy, min(a.xy,b.xy)-radius)) ||
        any(greaterThan(ray.xy, max(a.xy,b.xy)+radius))) continue;
    vec3 ba = b-a;
    vec3 oa = ray-a;
    float length2 = dot(ba,ba);
    float hit = min(sphereHit(ray,a,radius), sphereHit(ray,b,radius));
    float k2 = dot(ba.xy,ba.xy);
    if (length2 > 0.0000001 && k2 > 0.0000001) {
      float k1 = length2*oa.z - dot(oa,ba)*ba.z;
      float k0 = length2*(dot(oa,oa)-radius*radius)-dot(oa,ba)*dot(oa,ba);
      float discriminant = k1*k1-k2*k0;
      if (discriminant >= 0.0) {
        float t = (-k1-sqrt(discriminant))/k2;
        float along = dot(oa,ba)+t*ba.z;
        if (along >= 0.0 && along <= length2) hit = min(hit,t);
      }
    }
    if (hit > 0.0 && hit < closest) {
      closest = hit;
      vec3 position = ray+vec3(0.0,0.0,hit);
      float along = length2 > 0.0000001
          ? clamp(dot(position-a,ba)/length2,0.0,1.0) : 0.0;
      normal = normalize(position-a-along*ba);
    }
  }
  if (closest == 10000.0) {
    fragColor = vec4(0.0);
    return;
  }
  vec3 light = normalize(vec3(-0.45,0.7,-1.0));
  float diffuse = max(0.0,dot(normal,light));
  vec3 halfway = normalize(light+vec3(0.0,0.0,-1.0));
  float specular = pow(max(0.0,dot(normal,halfway)),28.0)*0.32;
  float depthFade = clamp(1.0-(closest-7.0)*0.13,0.65,1.0);
  // Body-relative two-tone material: pale front and saturated dark back.
  // A zero direction leaves degenerate/unknown orientations neutral.
  float facing = dot(normal,uForward);
  vec3 material = length(uForward) < 0.5 ? uColor
      : mix(uColor*0.45, mix(uColor,vec3(1.0),0.55),
            smoothstep(-0.15,0.15,facing));
  vec3 color = (material*(0.3+0.7*diffuse)+vec3(specular))*depthFade;
  fragColor = vec4(color,1.0);
}
