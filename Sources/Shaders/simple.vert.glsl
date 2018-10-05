#version 450

// Input vertex data, different for all executions of this shader
in vec3 pos;

uniform vec2 screenSize;
uniform float time;

uniform vec3 position;
uniform vec3 dir;
uniform vec3 up;

void main() {
	// Just output position
	gl_Position = vec4(pos, 1.0);
}