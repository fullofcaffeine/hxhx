package hxhx;

import backend.EmitResult;

private typedef CompilationRequestCleanup = {
	final name:String;
	final action:() -> Void;
}

/**
	Mutable working state that belongs to exactly one compiler request.

	The context owns ordered output, a cooperative cancellation deadline, staged
	filesystem output, and a reverse-order cleanup ledger. Compiler stages ask
	whether the request may continue at safe boundaries. Closing the context runs
	every cleanup even when an earlier one fails, reports those failures through
	the same request output, and rejects any later output writes.
**/
class CompilationRequestContext {
	public static inline final CANCELLED_EXIT_CODE:Int = 130;

	public final requestId:Int;
	public final output:CompilationRequestOutput;
	public final isServerRequest:Bool;

	final cleanupActions:Array<CompilationRequestCleanup>;
	final startedAtSeconds:Float;
	var closed:Bool;
	var cleanupSucceeded:Bool;
	var baselineReportEnabled:Bool;
	var deadlineAtSeconds:Null<Float>;
	var cancellationReason:Null<String>;
	var cancellationStage:Null<String>;
	var cancellationReported:Bool;
	var outputTransaction:Null<CompilationRequestOutputTransaction>;
	var stagedEmitResult:Null<EmitResult>;

	public function new(requestId:Int, bufferOutput:Bool, isServerRequest:Bool) {
		this.requestId = requestId;
		this.output = new CompilationRequestOutput(bufferOutput);
		this.isServerRequest = isServerRequest;
		this.cleanupActions = [];
		this.startedAtSeconds = haxe.Timer.stamp();
		this.closed = false;
		this.cleanupSucceeded = true;
		this.baselineReportEnabled = false;
		this.deadlineAtSeconds = null;
		this.cancellationReason = null;
		this.cancellationStage = null;
		this.cancellationReported = false;
		this.outputTransaction = null;
		this.stagedEmitResult = null;
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

	/** Set the maximum elapsed time for this request. Zero cancels at the next checkpoint. **/
	public function configureTimeoutMs(timeoutMs:Int):Void {
		ensureOpen();
		if (timeoutMs < 0 || timeoutMs > CompilationServerProtocol.MAX_REQUEST_TIMEOUT_MS)
			throw "compiler request timeout is outside the supported range";
		deadlineAtSeconds = startedAtSeconds + timeoutMs / 1000.0;
	}

	/** Ask cooperative compiler stages to stop this request at their next checkpoint. **/
	public function requestCancellation(reason:String):Void {
		ensureOpen();
		if (cancellationReason != null)
			return;
		final normalized = normalizeLabel(reason);
		if (normalized.length == 0)
			throw "compiler request cancellation reason is required";
		cancellationReason = normalized;
	}

	/**
		Return whether work may continue at a named safe boundary.

		The first failed checkpoint emits one stable diagnostic. Later checkpoints
		stay false without repeating it, while request cleanup still runs normally.
	**/
	public function checkpoint(stage:String):Bool {
		ensureOpen();
		if (cancellationReason == null && deadlineAtSeconds != null && haxe.Timer.stamp() >= deadlineAtSeconds)
			requestCancellation("deadline-exceeded");
		if (cancellationReason == null)
			return true;
		if (cancellationStage == null) {
			final normalizedStage = normalizeLabel(stage);
			cancellationStage = normalizedStage.length == 0 ? "unspecified" : normalizedStage;
		}
		if (!cancellationReported) {
			cancellationReported = true;
			output.stderrLine('hxhx(stage3): request cancelled [$cancellationReason] at $cancellationStage');
		}
		return false;
	}

	public function isCancelled():Bool {
		return cancellationReason != null;
	}

	/**
		Choose working paths for target output owned by this request.

		Direct commands keep their requested paths. Server requests receive private
		staging paths. Closing the request either publishes those paths after all
		other cleanup succeeds or removes them without changing prior output.
	**/
	public function prepareOutput(outDir:String, backendOutputDir:String, outputFileHint:Null<String>):CompilationRequestOutputPaths {
		ensureOpen();
		if (!isServerRequest)
			return CompilationRequestOutputPaths.direct(outDir, backendOutputDir, outputFileHint);
		if (outputTransaction != null)
			throw "compiler request output transaction is already prepared";
		final transaction = new CompilationRequestOutputTransaction(requestId, outDir, backendOutputDir, outputFileHint);
		outputTransaction = transaction;
		return transaction.outputPaths();
	}

	/** Seal completed server output for success-only publication during request close. **/
	public function sealOutput(result:EmitResult):EmitResult {
		ensureOpen();
		if (outputTransaction == null)
			return result;
		if (stagedEmitResult != null)
			throw "compiler request output is already sealed";
		stagedEmitResult = result;
		return outputTransaction.finalEmitResult(result);
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
	public function close(requestSucceeded:Bool = true):Bool {
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
		if (outputTransaction != null) {
			if (requestSucceeded && cleanupSucceeded && stagedEmitResult != null) {
				try {
					outputTransaction.publish();
				} catch (error:haxe.io.Error) {
					reportCleanupFailure("output-publication", Std.string(error));
				} catch (error:haxe.Exception) {
					reportCleanupFailure("output-publication", error.message);
				} catch (error:String) {
					reportCleanupFailure("output-publication", error);
				}
			}
			try {
				outputTransaction.close();
			} catch (error:haxe.io.Error) {
				reportCleanupFailure("output-transaction", Std.string(error));
			} catch (error:haxe.Exception) {
				reportCleanupFailure("output-transaction", error.message);
			} catch (error:String) {
				reportCleanupFailure("output-transaction", error);
			}
		}
		if (baselineReportEnabled)
			emitBaselineReport();
		output.close();
		return cleanupSucceeded;
	}

	public function isClosed():Bool {
		return closed;
	}

	function ensureOpen():Void {
		if (closed)
			throw "compiler request context is already closed";
	}

	static function normalizeLabel(value:String):String {
		if (value == null)
			return "";
		return StringTools.trim(value).split("\r").join(" ").split("\n").join(" ");
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
		output.stdoutLine("hxhx_server_report.cancelled=" + (isCancelled() ? "1" : "0"));
		if (cancellationReason != null) {
			output.stdoutLine("hxhx_server_report.cancellation_reason=" + cancellationReason);
			output.stdoutLine("hxhx_server_report.cancellation_stage=" + cancellationStage);
		}
		output.stdoutLine("hxhx_server_report.output_transaction=" + (outputTransaction == null ? "not_started" : outputTransaction.status()));
		output.stdoutLine("hxhx_server_report.cleanup=" + (cleanupSucceeded ? "ok" : "failed"));
		output.stdoutLine("hxhx_server_report.elapsed_ms=" + elapsedMs);
	}
}
