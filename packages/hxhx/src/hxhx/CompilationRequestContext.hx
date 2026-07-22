package hxhx;

private typedef CompilationRequestCleanup = {
	final name:String;
	final action:() -> Void;
}

/**
	Mutable working state that belongs to exactly one compiler request.

	The context owns ordered output and a reverse-order cleanup ledger. Compiler
	stages register resources or request-global compatibility state as soon as
	they acquire it. Closing the context runs every cleanup even when an earlier
	one fails, reports those failures through the same request output, and rejects
	any later output writes.

	Later `.32.1` slices add cancellation and staged filesystem output to this
	same request boundary instead of retaining them on the server process.
**/
class CompilationRequestContext {
	public final requestId:Int;
	public final output:CompilationRequestOutput;
	public final isServerRequest:Bool;

	final cleanupActions:Array<CompilationRequestCleanup>;
	final startedAtSeconds:Float;
	var closed:Bool;
	var cleanupSucceeded:Bool;
	var baselineReportEnabled:Bool;

	public function new(requestId:Int, bufferOutput:Bool, isServerRequest:Bool) {
		this.requestId = requestId;
		this.output = new CompilationRequestOutput(bufferOutput);
		this.isServerRequest = isServerRequest;
		this.cleanupActions = [];
		this.startedAtSeconds = haxe.Timer.stamp();
		this.closed = false;
		this.cleanupSucceeded = true;
		this.baselineReportEnabled = false;
	}

	public static function direct():CompilationRequestContext {
		return new CompilationRequestContext(0, false, false);
	}

	public static function server(requestId:Int):CompilationRequestContext {
		return new CompilationRequestContext(requestId, true, true);
	}

	/** Enable the opt-in report that proves this request reused no compiler facts. **/
	public function enableBaselineReport():Void {
		if (closed)
			throw "compiler request context is already closed";
		baselineReportEnabled = true;
	}

	/**
		Register one cleanup before exposing the acquired state to later stages.

		Cleanups run in reverse registration order, matching nested acquisition.
	**/
	public function registerCleanup(name:String, action:() -> Void):Void {
		if (closed)
			throw "compiler request context is already closed";
		if (name == null || StringTools.trim(name).length == 0)
			throw "compiler request cleanup name is required";
		if (action == null)
			throw "compiler request cleanup action is required";
		cleanupActions.push({name: StringTools.trim(name), action: action});
	}

	/**
		Close all registered request state and return whether every cleanup worked.

		The method is idempotent. A repeated close returns the result from the first
		close without running any action twice.
	**/
	public function close():Bool {
		if (closed)
			return cleanupSucceeded;
		closed = true;
		var index = cleanupActions.length;
		while (index > 0) {
			index -= 1;
			final cleanup = cleanupActions[index];
			try {
				cleanup.action();
			} catch (error:haxe.Exception) {
				reportCleanupFailure(cleanup.name, error.message);
			} catch (error:String) {
				reportCleanupFailure(cleanup.name, error);
			}
		}
		cleanupActions.resize(0);
		if (baselineReportEnabled)
			emitBaselineReport();
		output.close();
		return cleanupSucceeded;
	}

	public function isClosed():Bool {
		return closed;
	}

	function reportCleanupFailure(name:String, message:String):Void {
		cleanupSucceeded = false;
		output.stderrLine("hxhx(stage3): request cleanup failed [" + name + "]: " + message);
	}

	function emitBaselineReport():Void {
		final elapsedMs = Std.int(Math.max(0, (haxe.Timer.stamp() - startedAtSeconds) * 1000));
		output.stdoutLine("hxhx_server_report.request_id=" + requestId);
		output.stdoutLine("hxhx_server_report.server_request=" + (isServerRequest ? "1" : "0"));
		output.stdoutLine("hxhx_server_report.semantic_cache=disabled");
		output.stdoutLine("hxhx_server_report.semantic_cache_hits=0");
		output.stdoutLine("hxhx_server_report.semantic_cache_entries=0");
		output.stdoutLine("hxhx_server_report.cleanup=" + (cleanupSucceeded ? "ok" : "failed"));
		output.stdoutLine("hxhx_server_report.elapsed_ms=" + elapsedMs);
	}
}
