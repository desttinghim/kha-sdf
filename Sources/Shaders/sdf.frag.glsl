#version 450

uniform vec2 screenSize;
uniform float time;
out vec4 fragColor;

uniform vec3 position;
uniform vec3 look;
uniform vec3 up;

const int MAX_MARCHING_STEPS = 255;
const float MIN_DIST = 0.0;
const float MAX_DIST = 1000.0;
const float EPSILON = 0.0001;
const vec4 SKYCOLOR = vec4(0.31, 0.47, 0.67, 1.0);
const vec4 AMBIENT = vec4(0.15, 0.2, 0.32, 1.0);
const vec3 LIGHT0POSITION = vec3(0, 0, 0);
const vec4 LIGHTCOLOR = vec4(.5, .5, .5, 1.0);

// Maps x from [minX, maxX] to [minY, maxY], without clamping
float mapTo(float x, float minX, float maxX, float minY, float maxY) {
    float a = (maxY - minY) / (maxX - minX);
    float b = minY - a * minX;
    return a * x + b;
}

// Returns the unsigned distance estimate to a box of the given size
float udBox(vec3 p, vec3 size)
{
	return length(max(abs(p) - size, vec3(0.0)));
}

// Returns the signed distance estimate to a box of the given size
float sdBox(vec3 p, vec3 size)
{
	vec3 d = abs(p) - size;
	return min(max(d.x, max(d.y, d.z)), 0.0) + udBox(p, size);
}

// Returns signed distance of sphere with radius
float sdSphere(vec3 p, float radius)
{
	return length(p) - radius;
}

// Subtracts distance field db from da
float opSubtract(float da, float db) {
    return max(da, -db);
}

// Joins distance fields da and db
float opUnion(float da, float db) {
    return min(da, db);
}

// https://www.shadertoy.com/view/XsXfRH
float hash(vec3 p) {
    p  = 50.0 * fract( p*0.3183099 + vec3(0.71,0.113,0.419));
    return -1.0+2.0*fract( p.x*p.y*p.z*(p.x+p.y+p.z) );
}

// Return value noise (in x) and its derivatives (in yzw)
vec4 noised(vec3 x) {
    vec3 p = floor(x);
    vec3 w = fract(x);

    // cubic interpolation
    vec3 u = w*w*(3.0-2.0*w);
    vec3 du = 6.0*w*(1.0-w);
    
    float a = hash(p+vec3(0.0,0.0,0.0));
    float b = hash(p+vec3(1.0,0.0,0.0));
    float c = hash(p+vec3(0.0,1.0,0.0));
    float d = hash(p+vec3(1.0,1.0,0.0));
    float e = hash(p+vec3(0.0,0.0,1.0));
	float f = hash(p+vec3(1.0,0.0,1.0));
    float g = hash(p+vec3(0.0,1.0,1.0));
    float h = hash(p+vec3(1.0,1.0,1.0));
	
    float k0 =   a;
    float k1 =   b - a;
    float k2 =   c - a;
    float k3 =   e - a;
    float k4 =   a - b - c + d;
    float k5 =   a - c - e + g;
    float k6 =   a - b - e + f;
    float k7 = - a + b + c - d + e - f - g + h;

    return vec4( k0 + k1*u.x + k2*u.y + k3*u.z + k4*u.x*u.y + k5*u.y*u.z + k6*u.z*u.x + k7*u.x*u.y*u.z, 
                 du * vec3( k1 + k4*u.y + k6*u.z + k7*u.y*u.z,
                            k2 + k5*u.z + k4*u.x + k7*u.z*u.x,
                            k3 + k6*u.x + k5*u.y + k7*u.x*u.y ) );
}

// polynomial smooth min (k = 0.1);
float smin( float a, float b, float k )
{
    float h = max( k-abs(a-b), 0.0 );
    return min( a, b ) - h*h*0.25/k;
}

float displacement( vec3 p ) {
    const float a = 1.5;
    return sin(a * p.x) * sin(a * p.z);
}

// Returns the closest distance to a surface from p in our scene
float distScene(vec3 p) {
    // Cool sphere fractal
	float db = sdSphere(p, 2.0);
	vec3 q = mod(p.xyz, 0.5) - vec3(0.25);
	float d1 = opSubtract(db, sdBox(q, vec3(0.2)));

    float d2 = 10000.0;

    for(int i = 0; i >= 5; i++) {
        for(int j = 0; j >= 5; j++) {
            vec3 a = p - vec3((i-2) * 5.0, -1.0, (j-5) * 5.0);
            float n = 5.0 - distance(vec2(i, j), vec2(1, 1));
            d2 = smin(d2, sdSphere(a, n) + displacement(a), 0.1); 
        }
    }
    
	return opUnion(d1, d2);
    // p.xyz = mod(p.xyz, 5.0) - vec3(2.5);
    // return sdSphere(p, 0.25);
}

// Approximates normal
vec3 getNormal(vec3 p) {
	float h = 0.0001;
	return normalize(vec3(
		distScene(p + vec3(h, 0, 0)) - distScene(p - vec3(h, 0, 0)),
		distScene(p + vec3(0, h, 0)) - distScene(p - vec3(0, h, 0)),
		distScene(p + vec3(0, 0, h)) - distScene(p - vec3(0, 0, h))));
}

// Returns a value between 0 and 1 depending on how visible p0 is from p1
// 0 means it's completely blocked, 1 means completely visible
// k defines the hardness of the shadow
float getShadow(vec3 p0, vec3 p1, float k) {
    vec3 rd = normalize(p1 - p0);
    float t = 10.0 * EPSILON;
    float maxt = length(p0 - p1);
    float f = 1.0;
    for(int i = 0; i< MAX_MARCHING_STEPS; ++i)
    {
        float d = distScene(p0 + rd * t);

        // A surface was hit before we reached p1
        if (d < EPSILON)
            return 0.0;

        // Penumbra factor is calculated based on how close we were to
        // the surface, and how far away we are from the shading point
		// See http://www.iquilezles.org/www/articles/rmshadows/rmshadows.htm
        f = min(f, k * d / t);
        t += d;

        // We reached p1
        if (t >= maxt) 
            break;
    }

    return f;
}

// Calculate the light intensity with soft shadows
// p: point on surface
// lightPos: position of the light source
// lightColor: the radiance of the light source
// returns: the color of the point
vec4 getShading(vec3 p, vec3 normal, vec3 lightPos, vec4 lightColor) {
    float lightIntensity = 0.0;
    float shadow = getShadow(p, lightPos, 16.0);
    if (shadow > 0.0) { // If we are at all visible
        vec3 lightDirection = normalize(lightPos - p);
        lightIntensity = shadow * clamp(dot(normal, lightDirection), 0.0, 1.0);
    }

    return lightColor * lightIntensity + AMBIENT * (1.0 - lightIntensity);
}


// lightPos: position of the light source
// lightColor: the radiance of the light source
// returns: the color of the point
void raymarch(vec3 ro, vec3 rd, out int i, out float t) {
    t = 0.0;
    for (int j =0; j < MAX_MARCHING_STEPS; ++i) {
        vec3 p = ro + rd * t;
        float d = distScene(p);
        if(d < EPSILON || t > MAX_DIST) {
            i = j;
            break;
        }
        t += d;
    }
}

// lightPos: position of the light source
// lightColor: the radiance of the light source
// returns: the color of the point
float ambientOcclusion(vec3 p, vec3 n) {
    float stepSize = 0.01;
    float t = stepSize;
    float oc = 0.0;
    for (int i = 0; i < 10; ++i) {
        float d = distScene(p + n * t);
        oc += t - d; // Actual distance to surface - distance field value
        t += stepSize;
    }

    return clamp(oc, 0.0, 1.0);
}

// Create a checkboard texture
vec4 getFloorTexture(vec3 p) {
    vec2 m = mod(p.xz, 2.0) - vec2(1.0);
    return m.x * m.y > 0.0 ? vec4(0.1) : vec4(1.0);
}

// To improve perf, we raytrace the floor
// n: floor normal
// o: floor position
float raytraceFloor(vec3 ro, vec3 rd, vec3 n, vec3 o) {
    return dot(o - ro, n) / dot(rd, n);
}

// Computes the color corresponding to the ray intersection point (if any)
vec4 computeColor(vec3 ro, vec3 rd) {
    float t0;
    int i;
    raymarch(ro, rd, i, t0);
    
    vec3 floorNormal = vec3(0, 1, 0);
    float t1 = raytraceFloor(ro, rd, floorNormal, vec3(0, -0.5, 0));

    vec3 p; // Surface point
    vec3 normal; // Surface normal
    float t; // Distance traveled by ray from eye
    vec4 texture = vec4(1.0); // Surface texture

    if (t1 < t0 && t1 >= MIN_DIST && t1 <= MAX_DIST)  { // The floor was closest
        t = t1;
        p = ro + rd * t1;
        normal = floorNormal;
        texture = getFloorTexture(p);
    } else if(i < MAX_MARCHING_STEPS && t0 >= MIN_DIST && t0 <= MAX_DIST) {
        t = t0;
        p = ro + rd * t0;
        normal = getNormal(p);
    } else {
        return SKYCOLOR;
    }

    vec4 color;
    float z = mapTo(t, MIN_DIST, MAX_DIST, 1.0, 0.0);

    // Color based on depth
	//color = vec4(1.0) * z;

    // Diffuse lighting
    color = texture * (
        getShading(p, normal, position, LIGHTCOLOR) +
        getShading(p, normal, vec3(2.0, 3.0, 0.0), vec4(1.0, 0.5, 0.5, 1.0))
        ) / 2.0;

    // Color based on surface normal
    //color = vec4(abs(normal), 1.0);

    // Blend in ambient occlusion factor
    float ao = ambientOcclusion(p, normal);
    color = color * (1.0 - ao);

    // Blend the background color based on the distance from the camera
    float zSqrd = z * z;
    color = mix(SKYCOLOR, color, zSqrd * (3.0 - 2.0 * z)); // Fog

    return color;
}

/**
 * Return the normalized direction to march in from the eye point for a single pixel.
 * 
 * fieldOfView: vertical field of view in degrees
 * size: resolution of the output image
 * fragCoord: the x,y coordinate of the pixel in the output image
 */
vec3 rayDirection(float fieldOfView, vec2 size, vec2 fragCoord) {
    vec2 xy = fragCoord - size / 2.0;
    float z = size.y / tan(radians(fieldOfView) / 2.0);
    return normalize(vec3(xy, -z));
}

/**
 * Return a transform matrix that will transform a ray from view space
 * to world coordinates, given the eye point, the camera target, and an up vector.
 *
 * This assumes that the center of the camera is aligned with the negative z axis in
 * view space when calculating the ray marching direction. See rayDirection.
 */
mat4 viewMatrix(vec3 eye, vec3 center, vec3 up) {
    // Based on gluLookAt man page
    vec3 f = normalize(center - eye);
    vec3 s = normalize(cross(f, up));
    vec3 u = cross(s, f);
    return mat4(
        vec4(s, 0.0),
        vec4(u, 0.0),
        vec4(-f, 0.0),
        vec4(0.0, 0.0, 0.0, 1)
    );
}

void main() {
    float aspectRatio = screenSize.x / screenSize.y;
    vec3 ro = position;
    vec3 vd = rayDirection(45.0, screenSize.xy, gl_FragCoord.xy);
    mat4 viewToWorld = viewMatrix(ro, 
								look, 
								up);
    vec3 rd = (viewToWorld * vec4(vd, 0.0)).xyz;

    vec4 color = computeColor(ro, rd);

    fragColor = vec4(color.xyz, 1.0);
}