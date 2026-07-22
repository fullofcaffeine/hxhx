package hxhx;

/**
	Mutable working state that belongs to exactly one compiler request.

	This first version owns ordered output and lifecycle closure. Later `.32.1`
	slices add diagnostics, cancellation, output staging, and cleanup registrations
	to this same request boundary instead of retaining them on the server process.
**/
class CompilationRequestContext {
	public final requestId:Int;
	public final output:CompilationRequestOutput;
	public final isServerRequest:Bool;

	var closed:Bool;

	public function new(requestId:Int, bufferOutput:Bool, isServerRequest:Bool) {
		this.requestId = requestId;
		this.output = new CompilationRequestOutput(bufferOutput);
		this.isServerRequest = isServerRequest;
		this.closed = false;
	}

	public static function direct():CompilationRequestContext {
		return new CompilationRequestContext(0, false, false);
	}

	public static function server(requestId:Int):CompilationRequestContext {
		return new CompilationRequestContext(requestId, true, true);
	}

	public function close():Void {
		if (closed)
			return;
		closed = true;
		output.close();
	}

	public function isClosed():Bool {
		return closed;
	}
}
