
import kha.graphics4.hxsl.Shader;

class SDFShader extends Shader {
	static var SRC = {
		@input var input : { pos : Vec3 };
		var output : { position : Vec4, color : Vec4 };

		// Uniform values
		@param var time : Float;
		@param var screenSize : Vec3;
		@param var position : Vec3;
		@param var look : Vec3;
		@param var up : Vec3;

		// Constant values
		@param @const var maxMarchingSteps : Int;
		@param @const var minDist : Float;
		@param @const var maxDist : Float;
		@param @const var epsilon : Float;

		// Short a simple
		function vertex() {
			output.position = vec4(input.pos, 1.);
		}

		function fragment() {
			function sphereSDF(samplePoint : Vec3) {
				return length(samplePoint) - 1.0;
			}

			function sceneSDF(samplePoint : Vec3) {
				var d1 = sphereSDF(samplePoint);
				return d1;
			}

			function rayDirection(fov : Float, size : Vec2, fragCoord : Vec2) {
				var xy = fragCoord - size / 2.0;
				var z = size.y / tan(radians(fov) / 2.0);
				return normalize(vec3(xy, -z));
			}

			function viewMatrix(eye, look, up) {
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

			function shortestDistanceToSurface(eye : Vec3, dir : Vec3, start: Float, end : Float) {
				var depth = start;
				for (i in 0...maxMarchingSteps) {
					var dist = sceneSDF(eye + depth * dir);
					if (dist < epsilon) {return depth;}
					depth += dist;
					if (depth >= end) {return end;}
				}
				return end;
			}

			var viewDir : Vec3 = rayDirection(45.0, screenSize, gl_FragCoord.xy);
			var eye : Vec3 = position;

			var viewToWorld = viewMatrix(eye, look, up);

			var color : Vec4 = vec4(0.0);

			var worldDir = viewToWorld * vec4(viewDir, 0.0).xyz;

			var dist = shortestDistanceToSurface(eye, worldDir, minDist, maxDist));

			if (dist < end) {
				color = vec4(1.0);
			}

			output.color = color;

		}
	};

	public function new() {
		super();
		maxMarchingSteps.set(255);
		minDist.set(0.001);
		maxDist.set(500.0);
		epsilon.set(.0001);
	}
}