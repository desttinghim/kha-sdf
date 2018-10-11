#version 450

uniform vec2 screenSize;
uniform float time;
out vec4 fragColor;

uniform vec3 position;
uniform vec3 look;
uniform vec3 up;

const int MAX_MARCHING_STEPS = 255;
const float MIN_DIST = 0.0;
const float MAX_DIST = 500.0;
const float EPSILON = 0.0001;

struct HitObject
{
    float dist;
    vec3 color;
    vec3 hitPos;
};

// SDF Shapes

vec3 transformSDF( vec3 p, mat3 t ) {
    return t * p;
}

mat4 transpose(mat4 m) {
    return mat4(
        vec4( m[0][0], m[1][0], m[2][0], m[3][0] ),
        vec4( m[0][1], m[1][1], m[2][1], m[3][1] ),
        vec4( m[0][2], m[1][2], m[2][2], m[3][2] ),
        vec4( m[0][3], m[1][3], m[2][3], m[3][3] )
    );
}

/**
 * Signed distance function for a sphere centered at the origin with radius 1.0;
 */
HitObject sphereSDF(vec3 ray, vec3 size, vec3 color, mat4 transform) {
    vec3 rayPrime = vec3(transpose(transform) * vec4(ray, 1));
    float d = length(rayPrime-size);

    HitObject hitObject;
    hitObject.dist = d;
    hitObject.color = color;

    return hitObject;
}

/**
 * Signed distance function for a cube centered at the origin with radius 1.0;
 */
float boxSDF(vec3 p, vec3 b) {
    vec3 d = abs(p) - b;
	return min(max(d.x, max(d.y, d.z)), 0.0) + length(max(d, 0.0));
}

float planeSDF( vec3 samplePoint, vec4 n ) {
    // n must be normalized
    return dot(samplePoint, n.xyz) + n.w;
}

// SDF Operations

float intersectSDF(float distA, float distB) {
	return max(distA, distB);
}

float unionSDF(float distA, float distB) {
	return min(distA, distB);
}

float differenceSDF(float distA, float distB) {
	return max(distA, distB);
}

vec3 repeat(vec3 samplePoint, vec3 repetition) {
    vec3 p = samplePoint;
    vec3 c = repetition;
    return mod(p,c)-0.5*c;
}

/**
 * Signed distance function describing the scene.
 * 
 * Absolute value of the return value indicates the distance to the surface.
 * Sign indicates whether the point is inside or outside the surface,
 * negative indicating inside.
 */
float sceneSDF(vec3 samplePoint) {
	//float sphereDist = sphereSDF(samplePoint - vec3(0.0, 1.0, 0.0));
	float cubeDist = boxSDF(samplePoint - vec3(2.0, 2.0, 1.0), vec3(1.0, 1.0, 1.0));
    float planeDist = planeSDF(samplePoint, vec4(0, 1, 0, 0));
    float result = unionSDF(cubeDist, planeDist);
    //result = unionSDF(cubeDist, result);
    return result;//intersectSDF(cubeDist, sphereDist);
}

/**
 * Return the shortest distance from the eyepoint to the scene surface along
 * the marching direction. If no part of the surface is found between start and end,
 * return end.
 * 
 * eye: the eye point, acting as the origin of the ray
 * marchingDirection: the normalized direction to march in
 * start: the starting distance away from the eye
 * end: the max distance away from the ey to march before giving up
 */
float shortestDistanceToSurface(vec3 eye, vec3 marchingDirection, float start, float end) {
    float depth = start;
    for (int i = 0; i < MAX_MARCHING_STEPS; i++) {
        float dist = sceneSDF(eye + depth * marchingDirection);
        if (dist < EPSILON) {
			return depth;
        }
        depth += dist;
        if (depth >= end) {
            return end;
        }
    }
    return end;
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
 * Using the gradient of the SDF, estimate the normal on the surface at point p.
 */
vec3 estimateNormal(vec3 p) {
	return normalize(vec3(
		sceneSDF(vec3(p.x + EPSILON, p.y, p.z)) - sceneSDF(vec3(p.x - EPSILON, p.y, p.z)),
        sceneSDF(vec3(p.x, p.y + EPSILON, p.z)) - sceneSDF(vec3(p.x, p.y - EPSILON, p.z)),
        sceneSDF(vec3(p.x, p.y, p.z  + EPSILON)) - sceneSDF(vec3(p.x, p.y, p.z - EPSILON))
	));
}

float shadow(vec3 ro, vec3 rd, float mint, float maxt) {
    float dist = shortestDistanceToSurface(ro, rd, mint, maxt);
    if (dist == maxt) {
        return 0.0;
    }
    return 1.0;
    // rd = normalize(rd);
    // for (float t=mint; t < maxt;) {
    //     float h = sceneSDF(ro + rd * t);
    //     if (h < 0.001) {
    //         return 0.0;
    //     }
    //     t += h;
    // }
    // return 1.0;
}

/**
 * Lighting contribution of a single point light source via Phong illumination.
 * 
 * The vec3 returned is the RGB color of the light's contribution.
 *
 * k_a: Ambient color
 * k_d: Diffuse color
 * k_s: Specular color
 * alpha: Shininess coefficient
 * p: position of point being lit
 * eye: the position of the camera
 * lightPos: the position of the light
 * lightIntensity: color/intensity of the light
 *
 * See https://en.wikipedia.org/wiki/Phong_reflection_model#Description
 */
vec3 phongContribForLight(vec3 k_d, vec3 k_s, float alpha, vec3 p, vec3 eye,
                          vec3 lightPos, vec3 lightIntensity) {
	vec3 N = estimateNormal(p);
	vec3 L = normalize(lightPos - p);
	vec3 V = normalize(eye - p);
	vec3 R = normalize(reflect(-L, N));

	float dotLN = dot(L, N);
	float dotRV = dot(R, V);

	if (dotLN < 0.0) {
		// Light not visible from this point on surface
		return vec3(0.0, 0.0, 0.0);
	}

	if (dotRV < 0.0) {
		// Light reflection in opposite direction as viewer, apply only diffuse
		// component
		return lightIntensity * (k_d * dotLN);
	}
	return lightIntensity * (k_d * dotLN + k_s * pow(dotRV, alpha));
}


/**
 * Lighting via Phong illumination.
 * 
 * The vec3 returned is the RGB color of that point after lighting is applied.
 * k_a: Ambient color
 * k_d: Diffuse color
 * k_s: Specular color
 * alpha: Shininess coefficient
 * p: position of point being lit
 * eye: the position of the camera
 *
 * See https://en.wikipedia.org/wiki/Phong_reflection_model#Description
 */

vec3 phongIllumination(vec3 k_a, vec3 k_d, vec3 k_s, float alpha, vec3 p, vec3 eye) {
	// Ambient light
	const vec3 ambientLight = 0.7 * vec3(1.0, 1.0, 1.0);
	vec3 color = ambientLight * k_a;

	// First light
	vec3 light1Pos = vec3(4.0 * sin(time),
						  2.0,
						  4.0 * cos(time));
	vec3 light1Intensity = vec3(0.4, 0.4, 0.4);

	color += phongContribForLight(k_d, k_s, alpha, p, eye,
								  light1Pos,
								  light1Intensity);
	
	// Second light
	vec3 light2Pos = vec3(2.0 * sin(0.37 * time),
                          2.0 * cos(0.37 * time),
                          2.0);
    vec3 light2Intensity = vec3(0.4, 0.4, 0.4);

    color += phongContribForLight(k_d, k_s, alpha, p, eye,
                                  light2Pos,
                                  light2Intensity);   

    // Shadows
    float shadowFactor = shadow(p, light1Pos - p, MIN_DIST, 10.0);

    return color * shadowFactor;
}


vec3 celShading(vec3 c1, vec3 c2, vec3 c3, vec3 p, vec3 eye) {
	vec3 N = estimateNormal(p);
    vec3 color;
    float intensity;
	vec3 light1Pos = vec3(4.0 * sin(time),
						  2.0,
						  4.0 * cos(time));
    vec3 lightDir = normalize(light1Pos - p);
    intensity = dot(lightDir, N);

    if (intensity > 0.95)
        color = c1;
    else if (intensity > .5)
        color = c2;
    else 
        color = c3;

    return color;
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

vec3 applyFog(vec3 rgb, float distance) {
    float fogAmount = 1.0 - exp(-distance * rgb.z);
    vec3 fogColor = vec3(0.5, 0.6, 0.7);
    return mix(rgb, fogColor, fogAmount);
}

void mainImage()
{
	vec3 viewDir = rayDirection(45.0, screenSize.xy, gl_FragCoord.xy);
    vec3 eye = position;
    
    mat4 viewToWorld = viewMatrix(eye, 
								look, 
								up);

    // mat4 viewToWorld = viewMatrix(eye, 
	// 							vec3(0.5 * sin(time / 10), 0.0, 0.5 * cos(time / 10)), 
	// 							vec3(0.0, 1.0, 0.0));
    
    vec3 worldDir = (viewToWorld * vec4(viewDir, 0.0)).xyz;

    float dist = shortestDistanceToSurface(eye, worldDir, MIN_DIST, MAX_DIST);
    
    if (dist > MAX_DIST - EPSILON) {
        // Didn't hit anything
        fragColor = vec4(0.0, 0.0, 0.0, 0.0);
		return;
    }

	// The closest point on the surface to the eyepoint along the view ray
    vec3 p = eye + dist * worldDir;
    
    vec3 K_a = vec3(0.2, 0.2, 0.2);
    vec3 K_d = vec3(0.7, 0.2, 0.2);
    vec3 K_s = vec3(1.0, 1.0, 1.0);
    float shininess = 10.0;
	
	vec3 color = phongIllumination(K_a, K_d, K_s, shininess, p, eye);
    color = applyFog(color, dist / 100);
    // if (shadow(p, eye, MIN_DIST, MAX_DIST) < 1.0) {
    //     color = vec3(0.0, 0.0, 0.1);
    // }
    
    fragColor = vec4(color, 1.0);
}

void main() {
	mainImage();
    //fragColor = vec4(1.0, 0.0, 0.0, 1.0);
}