package;

import kha.Framebuffer;
import kha.Color;
import kha.Shaders;
import kha.System;
import kha.Scheduler;
import kha.graphics4.PipelineState;
import kha.graphics4.VertexStructure;
import kha.graphics4.VertexBuffer;
import kha.graphics4.IndexBuffer;
import kha.graphics4.FragmentShader;
import kha.graphics4.VertexShader;
import kha.graphics4.VertexData;
import kha.graphics4.Usage;
import kha.math.FastVector2;
import kha.math.FastVector3;
import kha.math.FastMatrix4;
import kha.graphics4.ConstantLocation;

import kha.input.Keyboard;
import kha.input.KeyCode;
import kha.input.Mouse;
import kha.Image;

class Project {

	// An array of 3 vectors representing 3 vertices to form a triangle
	static var vertices:Array<Float> = [
	   -1.0, -1.0, 0.0, // Bottom-left
	    1.0, -1.0, 0.0, // Bottom-right
	   -1.0,  1.0, 0.0,  // Top-left

	    1.0,  1.0, 0.0,  // Top-right
	    1.0, -1.0, 0.0, // Bottom-right
	   -1.0,  1.0, 0.0  // Top-left
	];
	// Indices for our triangle, these will point to vertices above
	static var indices:Array<Int> = [
		0, // Bottom-left
		1, // Bottom-right
		2, // Top-left
		3,  // Top-right
		4,
		5
	];

	var vertexBuffer:VertexBuffer;
	var indexBuffer:IndexBuffer;
	var pipeline:PipelineState;

	var screenSizeID:ConstantLocation;
	var timeID:ConstantLocation;
	var positionID:ConstantLocation;
	var lookID:ConstantLocation;
	var upID:ConstantLocation;
	var sceneListID:ConstantLocation;
	var sceneList:Array<{pos:FastVector3, shape:Int}>;

	var lastTime:Float;

	var position:FastVector3 = new FastVector3(8.0, 5.0, 8.0); // Initial position: on +Z
	var direction:FastVector3;
	var up:FastVector3;
	var horizontalAngle = 3.14; // Initial horizontalAngle: towards -Z
	var verticalAngle = 0.0; // Initial verticalAngle: none

	var moveForward = 0.0;
	var moveBackward = 0.0;
	var strafeLeft = 0.0;
	var strafeRight = 0.0;
	var isMouseDown = false;

	var mouseX = 0.0;
	var mouseY = 0.0;
	var mouseDeltaX = 0.0;
	var mouseDeltaY = 0.0;

	var speed = 3.0; // 3 units / second
	var mouseSpeed = 0.005;

	var tempBuffer:Image;
	var xres = 512;
	var yres = 300;

	public function new() {
		// Define vertex structure
		var structure = new VertexStructure();
        structure.add("pos", VertexData.Float3);
        // Save length - we only store position in vertices for now
        // Eventually there will be texture coords, normals,...
        var structureLength = 3;
	
		// Compile pipeline state
		// Shaders are located in 'Sources/Shaders' directory
        // and Kha includes them automatically
		pipeline = new PipelineState();
		pipeline.inputLayout = [structure];
		pipeline.fragmentShader = Shaders.sdf_frag;
		pipeline.vertexShader = Shaders.simple_vert;
		pipeline.compile();

		screenSizeID = pipeline.getConstantLocation("screenSize");
		timeID = pipeline.getConstantLocation("time");
		positionID = pipeline.getConstantLocation("position");
		lookID = pipeline.getConstantLocation("look");
		upID = pipeline.getConstantLocation("up");
		sceneListID = pipeline.getConstantLocation("sceneList");


		// Create vertex buffer
		vertexBuffer = new VertexBuffer(
			Std.int(vertices.length / 3), // Vertex count - 3 floats per vertex
			structure, // Vertex structure
			Usage.StaticUsage // Vertex data will stay the same
		);
		
		// Copy vertices to vertex buffer
		var vbData = vertexBuffer.lock();
		for (i in 0...vbData.length) {
			vbData.set(i, vertices[i]);
		}
		vertexBuffer.unlock();

		// Create index buffer
		indexBuffer = new IndexBuffer(
			indices.length, // 3 indices for our triangle
			Usage.StaticUsage // Index data will stay the same
		);
		
		// Copy indices to index buffer
		var iData = indexBuffer.lock();
		for (i in 0...iData.length) {
			iData[i] = indices[i];
		}
		indexBuffer.unlock();

		System.notifyOnRender(render);
		Scheduler.addTimeTask(update, 0, 1 / 60);

		lastTime = System.time;

		Mouse.get().notify(onMouseDown, onMouseUp, onMouseMove, null);
		Keyboard.get().notify(onKeyDown, onKeyUp);

		tempBuffer = Image.createRenderTarget(xres, yres);
    }

	public function render(frame:Framebuffer) {
		// A graphics object which lets us perform 3D operations
		var g = tempBuffer.g4;

		// Begin rendering
        g.begin();

        // Clear screen to black
		g.clear(Color.Black);

		// Bind state we want to draw with
		g.setPipeline(pipeline);

		// Bind data we want to draw
		g.setVertexBuffer(vertexBuffer);
		g.setIndexBuffer(indexBuffer);
		g.setVector2(screenSizeID, new FastVector2(xres, yres));
		g.setFloat(timeID, System.time);

		// Look vector
		var look = position.add(direction);
		g.setVector3(positionID, position);
		g.setVector3(lookID, look);
		g.setVector3(upID, up);
		// Kha apparently doesn't yet support UBO's, so I'll have to
		// find a workaround or move to a different framework
		//g.setTextureArray

		// Draw!
		g.drawIndexedVertices();

		// End rendering
		g.end();

		// Draw tempBuffer to screen, flipepd vertically
		frame.g2.begin();
		frame.g2.drawScaledImage(tempBuffer, 0, frame.height, frame.width, -frame.height);
		frame.g2.end();
    }

	function update() {
		var deltaTime = Scheduler.time() - lastTime;
		lastTime = Scheduler.time();

		// Compute new orientation
		if (isMouseDown) {
				horizontalAngle += mouseSpeed * mouseDeltaX * -1;
				verticalAngle += mouseSpeed * mouseDeltaY * -1;
		}

		// Direction: Spherical coordinates to Cartesian coordinates conversion
		direction = new FastVector3(
				Math.cos(verticalAngle) * Math.sin(horizontalAngle),
				Math.sin(verticalAngle),
				Math.cos(verticalAngle) * Math.cos(horizontalAngle)
		);

		// Right vector
		var right = new FastVector3(
				Math.sin(horizontalAngle - 3.14 / 2.0),
				0,
				Math.cos(horizontalAngle - 3.14 / 2.0)
		);

            // Up vector
		up = right.cross(direction);

		// Movement
		if (moveForward != 0 || moveBackward != 0) {
			var v = direction.mult(deltaTime * speed * (moveForward - moveBackward));
			position = position.add(v);
		}
		if (strafeRight != 0 || strafeLeft != 0) {
			var v = right.mult(deltaTime * speed * (strafeRight - strafeLeft));
			position = position.add(v);
		}

		mouseDeltaX = 0.0;
		mouseDeltaY = 0.0;
	}

	function onMouseDown(button:Int, x:Int, y:Int) {
            isMouseDown = true;
      }

      function onMouseUp(button:Int, x:Int, y:Int) {
            isMouseDown = false;
      }

      function onMouseMove(x:Int, y:Int, movementX:Int, movementY:Int) {
            mouseDeltaX = x - mouseX;
            mouseDeltaY = y - mouseY;

            mouseX = x;
            mouseY = y;
      }

      function onKeyDown(key:Int) {
            if (key == KeyCode.Up) moveForward = 1.0;
            if (key == KeyCode.Down) moveBackward = 1.0;
            if (key == KeyCode.Left) strafeLeft = 1.0;
            if (key == KeyCode.Right) strafeRight = 1.0;
      }

      function onKeyUp(key:Int) {
            if (key == KeyCode.Up) moveForward = 0.0;
            if (key == KeyCode.Down) moveBackward = 0.0;
            if (key == KeyCode.Left) strafeLeft = 0.0;
            if (key == KeyCode.Right) strafeRight = 0.0;
      }
}