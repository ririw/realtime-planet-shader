//=======================================================================================//
//
// Jupiter Shader — planet.fragment.glsl extended with ring system
// by Julien Sulpis (https://twitter.com/jsulpis)
// Forked by ririw (https://github.com/ririw/realtime-planet-shader) to add new planets
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

#define ROTATION_SPEED .1
#define PLANET_ROTATION rotateY(uTime * ROTATION_SPEED + uRotationOffset)

#define SUN_COLOR vec3(1.0, 1.0, 1.0)
#define DEEP_SPACE vec3(0., 0., 0.0005)

#define INFINITY 1e10
#define CAMERA_POSITION vec3(0., 0., 6.0)
#define FOCAL_LENGTH CAMERA_POSITION.z / (CAMERA_POSITION.z - uPlanetPosition.z)

#define PI acos(-1.)

// Jupiter's ring system — very faint, nearly edge-on
// Main ring: ~1.72–1.81 Rj; halo: ~1.4–1.72 Rj; gossamer rings extend further
// We use normalized units where planet radius = 2
#define RING_INNER 1.40
#define RING_OUTER 1.90
// Jupiter's rings are nearly in the equatorial plane, very slight tilt
#define RING_TILT 0.05

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

vec3 simpleReinhardToneMapping(vec3 color) {
  float exposure = 1.5;
  color *= exposure / (1. + color / exposure);
  color = pow(color, vec3(1. / 2.4));
  return color;
}

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

vec3 ringNormal() {
  return normalize(rotateX(RING_TILT) * vec3(0., 1., 0.));
}

float ringPlaneIntersect(vec3 ro, vec3 rd) {
  vec3 n = ringNormal();
  float denom = dot(rd, n);
  if(abs(denom) < 1e-6) return -1.;
  float t = dot(uPlanetPosition - ro, n) / denom;
  return t;
}

// Jupiter's rings: dusty, reddish-brown, very low opacity
// Halo (inner, diffuse) + main ring (narrow, slightly brighter) + gossamer (faint outer)
vec3 ringColor(float r) {
  float rNorm = (r - uPlanetRadius * RING_INNER) / (uPlanetRadius * (RING_OUTER - RING_INNER));
  rNorm = clamp(rNorm, 0., 1.);

  // Dusty reddish-brown color
  vec3 baseColor = vec3(0.55, 0.42, 0.30);

  float density = 0.0;

  // Halo — diffuse inner region
  float halo = smoothstep(0.0, 0.15, rNorm) * (1.0 - smoothstep(0.30, 0.45, rNorm));
  density += halo * 0.4;

  // Main ring — narrow, slightly brighter band
  float mainRing = smoothstep(0.42, 0.50, rNorm) * (1.0 - smoothstep(0.58, 0.65, rNorm));
  density += mainRing * 1.0;

  // Gossamer rings — very faint outer region
  float gossamer = smoothstep(0.63, 0.70, rNorm) * (1.0 - smoothstep(0.85, 1.0, rNorm));
  density += gossamer * 0.2;

  density = clamp(density, 0., 1.);

  return baseColor * density;
}

float ringAlpha(float r) {
  float rNorm = (r - uPlanetRadius * RING_INNER) / (uPlanetRadius * (RING_OUTER - RING_INNER));
  rNorm = clamp(rNorm, 0., 1.);

  float density = 0.0;
  float halo = smoothstep(0.0, 0.15, rNorm) * (1.0 - smoothstep(0.30, 0.45, rNorm));
  density += halo * 0.4;
  float mainRing = smoothstep(0.42, 0.50, rNorm) * (1.0 - smoothstep(0.58, 0.65, rNorm));
  density += mainRing * 1.0;
  float gossamer = smoothstep(0.63, 0.70, rNorm) * (1.0 - smoothstep(0.85, 1.0, rNorm));
  density += gossamer * 0.2;

  // Jupiter's rings are very faint — scale down overall opacity significantly
  return clamp(density, 0., 1.) * 0.25;
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

  vec3 n = ringNormal();
  float sunDot = abs(dot(uSunDirection, n));
  float lightFactor = mix(0.3, 1.0, sunDot) * uSunIntensity;

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

  bool ringInFront = ring.len > 0. && (hit.len >= INFINITY || ring.len < hit.len);
  bool ringBehind  = ring.len > 0. && hit.len < INFINITY && ring.len >= hit.len;

  vec3 ringBehindColor = vec3(0.);
  float ringBehindAlpha = 0.;
  if(ringBehind) {
    ringBehindColor = ring.color;
    ringBehindAlpha = ring.alpha;
  }

  if(hit.len < INFINITY) {
    spaceMask = 0.;

    float directLightIntensity = pow(clamp(dot(hit.normal, uSunDirection), 0.0, 1.0), 2.) * uSunIntensity;
    vec3 diffuseLight = directLightIntensity * SUN_COLOR;

    // Ring shadow on planet (very subtle for Jupiter's faint rings)
    float ringShadow = 1.0;
    {
      float rt = ringPlaneIntersect(hit.len * rd + ro, uSunDirection);
      if(rt > 0.001) {
        vec3 rp = (hit.len * rd + ro) + rt * uSunDirection;
        float rr = length(rp - uPlanetPosition);
        float innerR = uPlanetRadius * RING_INNER;
        float outerR = uPlanetRadius * RING_OUTER;
        if(rr >= innerR && rr <= outerR) {
          ringShadow = 1.0 - ringAlpha(rr) * 0.5;
        }
      }
    }

    vec3 diffuseColor = hit.material.color.rgb * (uAmbientLight + diffuseLight * ringShadow);

    vec3 reflected = normalize(reflect(-uSunDirection, hit.normal));
    float phongValue = pow(max(0.0, dot(rd, reflected)), 10.) * .2 * uSunIntensity;
    vec3 specularColor = hit.material.specular * vec3(phongValue);

    color = diffuseColor + specularColor + hit.material.emission;
  } else {
    float zoomFactor = min(uResolution.x / uResolution.y, 1.);
    vec3 backgroundRd = normalize(vec3(uv * zoomFactor, -1.));
    color = spaceColor(backgroundRd);

    color = mix(color, ringBehindColor, ringBehindAlpha);
  }

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
