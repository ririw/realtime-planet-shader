//=======================================================================================//
//
// Saturn Shader — planet.fragment.glsl extended with ring system
// by Julien Sulpis (https://twitter.com/jsulpis)
//
//=======================================================================================//

#version 300 es

precision highp float;
precision mediump int;
precision mediump sampler2D;

in vec2 uv;
out vec4 fragColor;

//===================//
//  Global uniforms  //
//===================//

uniform float uTime;
uniform vec2 uResolution;
uniform vec3 uPlanetPosition;
uniform float uPlanetRadius;
uniform float uRotationOffset;
uniform float uBumpStrength;
uniform sampler2D uPlanetColor;
uniform sampler2D uStars;

//==========================//
//  Controllable  uniforms  //
//==========================//

uniform vec3 uAtmosphereColor;
uniform float uAtmosphereDensity;
uniform float uSunIntensity;
uniform float uAmbientLight;
in vec3 uSunDirection;

//==========================================================//
//  Constants (could be turned into controllable uniforms)  //
//==========================================================//

// Planet geometry
#define ROTATION_SPEED .1
#define PLANET_ROTATION rotateY(uTime * ROTATION_SPEED + uRotationOffset)

// Lighting
#define SUN_COLOR vec3(1.0, 1.0, 1.0)
#define DEEP_SPACE vec3(0., 0., 0.0005)

// Ray tracing
#define INFINITY 1e10
#define CAMERA_POSITION vec3(0., 0., 6.0)
#define FOCAL_LENGTH CAMERA_POSITION.z / (CAMERA_POSITION.z - uPlanetPosition.z)

#define PI acos(-1.)

// Ring geometry — radii in world units (planet radius = 2)
// Saturn's rings span roughly 1.2x–2.3x the planet radius
#define RING_INNER 1.22
#define RING_OUTER 2.30
// Ring plane tilt (radians) — Saturn's rings are tilted ~27° to the ecliptic
#define RING_TILT 0.47

//=========//
//  Types  //
//=========//

struct Material {
  vec3 color;
  float diffuse;
  float specular;
  vec3 emission;
};

struct Hit {
  float len;
  vec3 normal;
  Material material;
};

struct Sphere {
  vec3 position;
  float radius;
};

Hit miss = Hit(INFINITY, vec3(0.), Material(vec3(0.), -1., -1., vec3(-1.)));

Sphere getPlanet() {
  return Sphere(uPlanetPosition, uPlanetRadius);
}

//===============================================//
//  Generic utilities stolen from smarter people //
//===============================================//

float inverseLerp(float v, float minValue, float maxValue) {
  return (v - minValue) / (maxValue - minValue);
}

float remap(float v, float inMin, float inMax, float outMin, float outMax) {
  float t = inverseLerp(v, inMin, inMax);
  return mix(outMin, outMax, t);
}

vec2 sphereProjection(vec3 p, vec3 origin) {
  vec3 dir = normalize(p - origin);
  float longitude = atan(dir.x, dir.z);
  float latitude = asin(dir.y);

  return vec2(
    (longitude + PI) / (2. * PI),
    (latitude + PI / 2.) / PI
  );
}

// https://iquilezles.org/articles/intersectors/
float sphIntersect(in vec3 ro, in vec3 rd, in Sphere sphere) {
  vec3 oc = ro - sphere.position;
  float b = dot(oc, rd);
  float c = dot(oc, oc) - sphere.radius * sphere.radius;
  float h = b * b - c;
  if(h < 0.0)
    return -1.;
  return -b - sqrt(h);
}

mat3 rotateY(float angle) {
  float c = cos(angle);
  float s = sin(angle);
  return mat3(
    vec3(c, 0, s),
    vec3(0, 1, 0),
    vec3(-s, 0, c)
  );
}

mat3 rotateX(float angle) {
  float c = cos(angle);
  float s = sin(angle);
  return mat3(
    vec3(1, 0, 0),
    vec3(0, c, -s),
    vec3(0, s, c)
  );
}

// Zavie - https://www.shadertoy.com/view/lslGzl
vec3 simpleReinhardToneMapping(vec3 color) {
  float exposure = 1.5;
  color *= exposure / (1. + color / exposure);
  color = pow(color, vec3(1. / 2.4));
  return color;
}

// https://www.shadertoy.com/view/MtX3z2
float Sigmoid (float x) {
  return 1.0 / (1.0 + (exp(-(x - 0.7) * 6.5)));
}

vec3 Scurve (vec3 color) {
  return vec3(Sigmoid(color.x), Sigmoid(color.y), Sigmoid(color.z));
}

//========//
//  Misc  //
//========//

float planetNoise(vec3 p) {
  vec2 textureCoord = sphereProjection(p, uPlanetPosition);
  float bump = length(texture(uPlanetColor, textureCoord));
  return uBumpStrength * bump;
}

float planetDist(in vec3 ro, in vec3 rd) {
  float smoothSphereDist = sphIntersect(ro, rd, getPlanet());

  vec3 intersection = ro + smoothSphereDist * rd;
  vec3 intersectionWithRotation = PLANET_ROTATION * (intersection - uPlanetPosition) + uPlanetPosition;

  return sphIntersect(ro, rd, Sphere(uPlanetPosition, uPlanetRadius + planetNoise(intersectionWithRotation)));
}

vec3 planetNormal(vec3 p) {
  vec3 rd = uPlanetPosition - p;
  float dist = planetDist(p, rd);
  vec2 e = vec2(max(.01, .03 * smoothstep(1300., 300., uResolution.x)), 0);

  vec3 normal = dist - vec3(planetDist(p - e.xyy, rd), planetDist(p - e.yxy, rd), planetDist(p + e.yyx, rd));
  return normalize(normal);
}

vec3 spaceColor(vec3 direction) {
  vec3 backgroundCoord = direction * rotateY(uTime * ROTATION_SPEED / 3. + 1.5);

  vec2 textureCoord = sphereProjection(backgroundCoord, vec3(0.));
  textureCoord.x = 1. - textureCoord.x;
  vec3 stars = texture(uStars, textureCoord).rgb;

  return DEEP_SPACE + stars * stars * stars * .5;
}

vec3 atmosphereColor(vec3 ro, vec3 rd, float spaceMask) {
  float distCameraToPlanetOrigin = length(uPlanetPosition - CAMERA_POSITION);
  float distCameraToPlanetEdge = sqrt(distCameraToPlanetOrigin * distCameraToPlanetOrigin - uPlanetRadius * uPlanetRadius);

  float planetMask = 1.0 - spaceMask;

  vec3 coordFromCenter = (ro + rd * distCameraToPlanetEdge) - uPlanetPosition;
  float distFromEdge = abs(length(coordFromCenter) - uPlanetRadius);
  float planetEdge = max(uPlanetRadius - distFromEdge, 0.) / uPlanetRadius;
  float atmosphereMask = pow(remap(dot(uSunDirection, coordFromCenter), -uPlanetRadius, uPlanetRadius / 2., 0., 1.), 5.);
  atmosphereMask *= uAtmosphereDensity * uPlanetRadius * uSunIntensity;

  vec3 atmosphere = vec3(pow(planetEdge, 120.)) * .5;
  atmosphere += pow(planetEdge, 50.) * .3 * (1.5 - planetMask);
  atmosphere += pow(planetEdge, 15.) * .015;
  atmosphere += pow(planetEdge, 5.) * .04 * planetMask;

  return atmosphere * uAtmosphereColor * atmosphereMask;
}

//==========//
//  Rings   //
//==========//

// Ring plane normal (tilted around X axis)
vec3 ringNormal() {
  return normalize(rotateX(RING_TILT) * vec3(0., 1., 0.));
}

// Returns the t along the ray where it hits the ring plane, or -1 if parallel/behind
float ringPlaneIntersect(vec3 ro, vec3 rd) {
  vec3 n = ringNormal();
  float denom = dot(rd, n);
  if(abs(denom) < 1e-6) return -1.;
  float t = dot(uPlanetPosition - ro, n) / denom;
  return t;
}

// Procedural ring density/color at a given radial distance (normalized 0..1 across ring width)
// Mimics Saturn's main ring bands: C, B, Cassini Division, A
vec3 ringColor(float r) {
  // r is distance from planet center in world units
  float rNorm = (r - uPlanetRadius * RING_INNER) / (uPlanetRadius * (RING_OUTER - RING_INNER));
  rNorm = clamp(rNorm, 0., 1.);

  // Base warm tan/beige color of Saturn's rings
  vec3 baseColor = vec3(0.82, 0.72, 0.55);

  // Band structure: C ring (inner, faint), B ring (bright), Cassini Division (gap), A ring
  float density = 0.0;

  // C ring — faint inner band
  float cRing = smoothstep(0.0, 0.08, rNorm) * (1.0 - smoothstep(0.08, 0.30, rNorm));
  density += cRing * 0.35;

  // B ring — brightest, widest band
  float bRing = smoothstep(0.28, 0.35, rNorm) * (1.0 - smoothstep(0.55, 0.62, rNorm));
  density += bRing * 1.0;

  // Cassini Division — dark gap between B and A rings
  float cassini = smoothstep(0.60, 0.64, rNorm) * (1.0 - smoothstep(0.64, 0.68, rNorm));
  density -= cassini * 0.9;

  // A ring — moderately bright outer band
  float aRing = smoothstep(0.66, 0.72, rNorm) * (1.0 - smoothstep(0.88, 0.96, rNorm));
  density += aRing * 0.7;

  // Fine sub-band variation within B ring using a simple hash-like pattern
  float subBands = sin(rNorm * 180.0) * 0.5 + 0.5;
  density *= mix(1.0, subBands * 0.4 + 0.6, bRing * 0.5);

  density = clamp(density, 0., 1.);

  // Slight color variation: inner rings are more grey, outer more golden
  vec3 color = mix(vec3(0.75, 0.70, 0.62), vec3(0.88, 0.78, 0.55), rNorm);

  return color * density;
}

// Returns ring alpha (opacity) at radial distance r
float ringAlpha(float r) {
  float rNorm = (r - uPlanetRadius * RING_INNER) / (uPlanetRadius * (RING_OUTER - RING_INNER));
  rNorm = clamp(rNorm, 0., 1.);

  float density = 0.0;
  float cRing = smoothstep(0.0, 0.08, rNorm) * (1.0 - smoothstep(0.08, 0.30, rNorm));
  density += cRing * 0.35;
  float bRing = smoothstep(0.28, 0.35, rNorm) * (1.0 - smoothstep(0.55, 0.62, rNorm));
  density += bRing * 1.0;
  float cassini = smoothstep(0.60, 0.64, rNorm) * (1.0 - smoothstep(0.64, 0.68, rNorm));
  density -= cassini * 0.9;
  float aRing = smoothstep(0.66, 0.72, rNorm) * (1.0 - smoothstep(0.88, 0.96, rNorm));
  density += aRing * 0.7;

  return clamp(density, 0., 1.);
}

struct RingHit {
  float len;
  vec3 color;
  float alpha;
};

RingHit intersectRing(vec3 ro, vec3 rd) {
  float t = ringPlaneIntersect(ro, rd);
  if(t < 0.001) return RingHit(-1., vec3(0.), 0.);

  vec3 hitPos = ro + t * rd;
  float r = length(hitPos - uPlanetPosition);

  float innerR = uPlanetRadius * RING_INNER;
  float outerR = uPlanetRadius * RING_OUTER;

  if(r < innerR || r > outerR) return RingHit(-1., vec3(0.), 0.);

  // Lighting: rings are lit from the sun direction
  vec3 n = ringNormal();
  float sunDot = abs(dot(uSunDirection, n)); // both faces lit
  float lightFactor = mix(0.3, 1.0, sunDot) * uSunIntensity;

  // Shadow of planet on rings: check if the hit point is in the planet's shadow
  // Cast a ray from hitPos toward the sun; if it hits the planet, it's in shadow
  float shadowT = sphIntersect(hitPos, uSunDirection, getPlanet());
  float shadow = (shadowT > 0.001) ? 0.15 : 1.0;

  vec3 col = ringColor(r) * lightFactor * shadow + ringColor(r) * uAmbientLight;
  float alpha = ringAlpha(r);

  return RingHit(t, col, alpha);
}

//===============//
//  Ray Tracing  //
//===============//

Hit intersectPlanet(vec3 ro, vec3 rd) {
  float len = sphIntersect(ro, rd, getPlanet());

  if(len < 0.) {
    return miss;
  }

  vec3 position = ro + len * rd;
  vec3 rotatedPosition = PLANET_ROTATION * (position - uPlanetPosition) + uPlanetPosition;

  vec2 textureCoord = sphereProjection(rotatedPosition, uPlanetPosition);
  vec3 color = texture(uPlanetColor, textureCoord).rgb;
  color = Scurve(color);

  vec3 normal = planetNormal(position);

  return Hit(len, normal, Material(color, 1., 0., vec3(0.)));
}

vec3 radiance(vec3 ro, vec3 rd) {
  vec3 color = vec3(0.);
  float spaceMask = 1.;
  Hit hit = intersectPlanet(ro, rd);

  RingHit ring = intersectRing(ro, rd);

  // Determine draw order: ring behind planet, ring in front of planet
  bool ringInFront = ring.len > 0. && (hit.len >= INFINITY || ring.len < hit.len);
  bool ringBehind  = ring.len > 0. && hit.len < INFINITY && ring.len >= hit.len;

  // Draw ring behind planet first (will be composited under planet)
  vec3 ringBehindColor = vec3(0.);
  float ringBehindAlpha = 0.;
  if(ringBehind) {
    ringBehindColor = ring.color;
    ringBehindAlpha = ring.alpha;
  }

  if(hit.len < INFINITY) {
    spaceMask = 0.;

    // Diffuse
    float directLightIntensity = pow(clamp(dot(hit.normal, uSunDirection), 0.0, 1.0), 2.) * uSunIntensity;
    vec3 diffuseLight = directLightIntensity * SUN_COLOR;

    // Ring shadow on planet: cast ray from surface toward sun; if it hits the ring plane
    // within ring bounds, darken the surface
    float ringShadow = 1.0;
    {
      float rt = ringPlaneIntersect(hit.len * rd + ro, uSunDirection);
      if(rt > 0.001) {
        vec3 rp = (hit.len * rd + ro) + rt * uSunDirection;
        float rr = length(rp - uPlanetPosition);
        float innerR = uPlanetRadius * RING_INNER;
        float outerR = uPlanetRadius * RING_OUTER;
        if(rr >= innerR && rr <= outerR) {
          ringShadow = 1.0 - ringAlpha(rr) * 0.7;
        }
      }
    }

    vec3 diffuseColor = hit.material.color.rgb * (uAmbientLight + diffuseLight * ringShadow);

    // Phong specular
    vec3 reflected = normalize(reflect(-uSunDirection, hit.normal));
    float phongValue = pow(max(0.0, dot(rd, reflected)), 10.) * .2 * uSunIntensity;
    vec3 specularColor = hit.material.specular * vec3(phongValue);

    color = diffuseColor + specularColor + hit.material.emission;

    // Composite ring behind planet over the planet (ring is behind, so it's already occluded)
    // (nothing to do — planet occludes the ring)
  } else {
    float zoomFactor = min(uResolution.x / uResolution.y, 1.);
    vec3 backgroundRd = normalize(vec3(uv * zoomFactor, -1.));
    color = spaceColor(backgroundRd);

    // Composite ring-behind over background
    color = mix(color, ringBehindColor, ringBehindAlpha);
  }

  // Composite ring in front of planet/background
  if(ringInFront) {
    color = mix(color, ring.color, ring.alpha);
  }

  return color + atmosphereColor(ro, rd, spaceMask);
}

//========//
//  Main  //
//========//

void main() {
  vec3 ro = vec3(CAMERA_POSITION);
  vec3 rd = normalize(vec3(uv * FOCAL_LENGTH, -1.));

  vec3 color = radiance(ro, rd);

  color = simpleReinhardToneMapping(color);
  color *= 1. - 0.5 * pow(length(uv), 3.);

  fragColor = vec4(color, 1.0);
}
