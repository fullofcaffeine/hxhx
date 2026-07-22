import haxe.io.Bytes;
import hxhx.CompilationRequestContext;
import hxhx.CompilationRequestOutputEvent;
import hxhx.CompilationServerReply;
import hxhx.CompilationServerProtocol;
import hxhx.CompilationServerRequest;
import hxhx.CompilationServerRequestCodec;
import hxhx.CompilationServerRequestDispatcher;
import hxhx.CompilationServerStopSignal;
import hxhx.Stage3Compiler;
import hxhx.macro.MacroState;
import sys.FileSystem;
import sys.io.File;

class M14CompilationServerRequestDispatcherIntegrationTest {
	static function assertTrue(condition:Bool, message:String):Void {
		if (!condition)
			throw message;
	}

	static function assertEquals(actual:String, expected:String, label:String):Void {
		assertTrue(actual == expected, label + " mismatch: expected `" + expected + "`, got `" + actual + "`");
	}

	static function assertArgs(actual:Array<String>, expected:Array<String>, label:String):Void {
		assertEquals(actual.join("\n"), expected.join("\n"), label);
	}

	static function reply(events:Array<CompilationRequestOutputEvent>, isError:Bool):CompilationServerReply {
		return new CompilationServerReply(events, isError);
	}

	static function deleteRecursive(path:String):Void {
		if (!FileSystem.exists(path))
			return;
		if (FileSystem.isDirectory(path)) {
			for (entry in FileSystem.readDirectory(path))
				deleteRecursive(haxe.io.Path.join([path, entry]));
			FileSystem.deleteDirectory(path);
		} else {
			FileSystem.deleteFile(path);
		}
	}

	static function main():Void {
		assertTrue(CompilationServerProtocol.requestLengthProblem(0) == null, "empty framed request should be representable");
		assertTrue(CompilationServerProtocol.requestLengthProblem(CompilationServerProtocol.MAX_REQUEST_BYTES) == null,
			"request at the byte limit should be accepted");
		assertTrue(CompilationServerProtocol.requestLengthProblem(-1).indexOf("negative") >= 0, "negative request length should be rejected");
		assertTrue(CompilationServerProtocol.requestLengthProblem(CompilationServerProtocol.MAX_REQUEST_BYTES + 1).indexOf("maximum") >= 0,
			"request over the byte limit should be rejected");
		assertTrue(CompilationServerProtocol.parseRequestTimeoutMs("0") == 0, "zero timeout should request cancellation at the first checkpoint");
		assertTrue(CompilationServerProtocol.parseRequestTimeoutMs("250") == 250, "decimal timeout should be accepted");
		assertTrue(CompilationServerProtocol.parseRequestTimeoutMs("-1") == null, "negative timeout should be rejected");
		assertTrue(CompilationServerProtocol.parseRequestTimeoutMs("1ms") == null, "timeout units should not be accepted inside the numeric value");
		assertTrue(CompilationServerProtocol.parseRequestTimeoutMs(Std.string(CompilationServerProtocol.MAX_REQUEST_TIMEOUT_MS + 1)) == null,
			"timeout above the protocol maximum should be rejected");

		final baseArgs = ["--hxhx-no-emit", "--hxhx-out", "out"];
		final requestArgs = ["-cp", "src", "-main", "Main"];
		final direct = new CompilationServerRequest(7, baseArgs, requestArgs, Bytes.ofString("original input"));
		baseArgs[0] = "mutated base";
		requestArgs[0] = "mutated request";
		assertArgs(direct.invocationArgs(), ["--hxhx-no-emit", "--hxhx-out", "out", "-cp", "src", "-main", "Main"], "request constructor copy");
		final timedArgs = new CompilationServerRequest(70, ["--hxhx-no-run"], [
			"-main",
			"Main",
			CompilationServerProtocol.REQUEST_TIMEOUT_FLAG,
			"25",
			"-cp",
			"src"
		], null);
		assertArgs(timedArgs.compilerArgs(), ["--hxhx-no-run", "-main", "Main", "-cp", "src"], "server timeout removal from compiler arguments");

		final firstInput = direct.stdinBytes();
		assertTrue(firstInput != null, "request should return copied display input");
		firstInput.set(0, "X".code);
		final secondInput = direct.stdinBytes();
		assertTrue(secondInput != null, "request should retain display input after caller mutation");
		assertEquals(secondInput.getString(0, secondInput.length), "original input", "request input copy");

		final decoded = CompilationServerRequestCodec.decodeString(8, ["--base"], "--display\r\nMain.hx@0@diagnostics\n-cp\nsrc\n\x01class Main {}");
		assertTrue(decoded.requestId == 8, "codec should retain the request ID");
		assertArgs(decoded.requestArgs(), ["--display", "Main.hx@0@diagnostics", "-cp", "src"], "decoded request args");
		assertEquals(decoded.findFlagValue("--display"), "Main.hx@0@diagnostics", "display flag");
		final decodedInput = decoded.stdinBytes();
		assertTrue(decodedInput != null, "codec should preserve display stdin");
		assertEquals(decodedInput.getString(0, decodedInput.length), "class Main {}", "decoded display stdin");

		var compileCalls = 0;
		var compiledArgs = new Array<String>();
		final compileReply = CompilationServerRequestDispatcher.dispatch(direct, (args, context) -> {
			compileCalls += 1;
			compiledArgs = args;
			context.output.stdoutLine("compiled");
			return 0;
		});
		assertTrue(compileCalls == 1, "ordinary request should call the shared compiler exactly once");
		assertArgs(compiledArgs, direct.invocationArgs(), "shared compile invocation");
		assertTrue(!compileReply.isError, "successful compile should not be an error reply");
		assertEquals(CompilationServerRequestCodec.encodeReply(compileReply), "\x01compiled\x01\n", "successful compile reply");

		final failedReply = CompilationServerRequestDispatcher.dispatch(direct, (_, context) -> {
			context.output.stderrLine("specific failure");
			return 1;
		});
		assertTrue(failedReply.isError, "failed compile should return an error reply");
		assertEquals(CompilationServerRequestCodec.encodeReply(failedReply), "specific failure\n\x02\n", "failed compile reply");

		var escapedContext:Null<CompilationRequestContext> = null;
		final thrownReply = CompilationServerRequestDispatcher.dispatch(direct, (_, context) -> {
			escapedContext = context;
			throw "request exploded";
		});
		assertTrue(thrownReply.isError, "thrown compiler request should return an error reply");
		assertTrue(escapedContext != null && escapedContext.isClosed(), "thrown compiler request should close its request context");
		assertTrue(CompilationServerRequestCodec.encodeReply(thrownReply).indexOf("request exploded") >= 0,
			"thrown compiler request should preserve the original failure");

		final cleanupContext = CompilationRequestContext.server(9);
		final cleanupOrder = new Array<String>();
		cleanupContext.registerCleanup("first", () -> cleanupOrder.push("first"));
		cleanupContext.registerCleanup("second", () -> cleanupOrder.push("second"));
		assertTrue(cleanupContext.close(), "successful cleanup should report success");
		assertEquals(cleanupOrder.join(","), "second,first", "request cleanup order");
		assertTrue(cleanupContext.close(), "a repeated close should retain the first cleanup result");
		var lateWriteRejected = false;
		try {
			cleanupContext.output.stdoutLine("too late");
		} catch (_:String) {
			lateWriteRejected = true;
		}
		assertTrue(lateWriteRejected, "closed request output should reject a late write");

		final cancelledContext = CompilationRequestContext.server(90);
		cancelledContext.requestCancellation("fixture-request");
		assertTrue(!cancelledContext.checkpoint("fixture-stage"), "cancelled request should stop at its next checkpoint");
		assertTrue(!cancelledContext.checkpoint("later-stage"), "cancelled request should remain cancelled");
		final cancellationEvents = cancelledContext.output.events();
		assertTrue(cancellationEvents.length == 1, "cancellation should emit one diagnostic even across repeated checkpoints");
		assertTrue(cancellationEvents[0].text.indexOf("request cancelled [fixture-request] at fixture-stage") >= 0,
			"cancellation diagnostic should identify its reason and first observed stage");
		assertTrue(cancelledContext.close(), "cancelled request should still close cleanly");

		final cleanupFailureReply = CompilationServerRequestDispatcher.dispatch(direct, (_, context) -> {
			context.registerCleanup("broken-fixture", () -> throw "cleanup exploded");
			return 0;
		});
		final cleanupFailureWire = CompilationServerRequestCodec.encodeReply(cleanupFailureReply);
		assertTrue(cleanupFailureReply.isError, "cleanup failure should fail an otherwise successful request");
		assertTrue(cleanupFailureWire.indexOf("request cleanup failed [broken-fixture]: cleanup exploded") >= 0,
			"cleanup failure should reach the requesting client");

		final reportReply = CompilationServerRequestDispatcher.dispatch(new CompilationServerRequest(10, ["--hxhx-server-report"], [], null), (_, _) -> 0);
		final reportWire = CompilationServerRequestCodec.encodeReply(reportReply);
		assertTrue(!reportReply.isError, "zero-cache baseline report should not fail the request");
		assertTrue(reportWire.indexOf("hxhx_server_report.request_id=10") >= 0, "baseline report should identify its request");
		assertTrue(reportWire.indexOf("hxhx_server_report.semantic_cache=disabled") >= 0, "baseline report should say semantic caching is disabled");
		assertTrue(reportWire.indexOf("hxhx_server_report.semantic_cache_hits=0") >= 0, "baseline report should report zero semantic cache hits");
		assertTrue(reportWire.indexOf("hxhx_server_report.cleanup=ok") >= 0, "baseline report should include cleanup status");
		assertTrue(reportWire.indexOf("hxhx_server_report.cancelled=0") >= 0, "baseline report should say an ordinary request was not cancelled");

		var timedCompileCalls = 0;
		final timedReply = CompilationServerRequestDispatcher.dispatch(new CompilationServerRequest(12, ["--hxhx-server-report"],
			[CompilationServerProtocol.REQUEST_TIMEOUT_FLAG, "0", "-main", "Main"], null),
			(_, _) -> {
				timedCompileCalls += 1;
				return 0;
			});
		final timedWire = CompilationServerRequestCodec.encodeReply(timedReply);
		assertTrue(timedCompileCalls == 0, "an expired request should stop before calling the compiler");
		assertTrue(timedReply.isError, "an expired request should return an error reply");
		assertTrue(timedWire.indexOf("request cancelled [deadline-exceeded] at request-dispatch") >= 0,
			"expired request should identify its cancellation boundary");
		assertTrue(timedWire.indexOf("hxhx_server_report.cancelled=1") >= 0, "expired request report should record cancellation");
		assertTrue(timedWire.indexOf("hxhx_server_report.cancellation_reason=deadline-exceeded") >= 0, "expired request report should record its reason");

		var invalidTimeoutCompileCalls = 0;
		final invalidTimeoutReply = CompilationServerRequestDispatcher.dispatch(new CompilationServerRequest(13, [],
			[CompilationServerProtocol.REQUEST_TIMEOUT_FLAG, "soon"], null), (_, _) -> {
				invalidTimeoutCompileCalls += 1;
				return 0;
			});
		assertTrue(invalidTimeoutCompileCalls == 0, "invalid timeout should fail before calling the compiler");
		assertTrue(invalidTimeoutReply.isError, "invalid timeout should return an error reply");
		assertTrue(CompilationServerRequestCodec.encodeReply(invalidTimeoutReply).indexOf("must be a decimal integer") >= 0,
			"invalid timeout should explain the accepted format");

		final cooperativeCancellationReply = CompilationServerRequestDispatcher.dispatch(new CompilationServerRequest(131, [], [], null), (_, context) -> {
			context.requestCancellation("fixture-mid-request");
			return context.checkpoint("fixture-compiler-stage") ? 0 : CompilationRequestContext.CANCELLED_EXIT_CODE;
		});
		final cooperativeCancellationWire = CompilationServerRequestCodec.encodeReply(cooperativeCancellationReply);
		assertTrue(cooperativeCancellationReply.isError, "compiler-stage cancellation should fail only its request");
		assertTrue(cooperativeCancellationWire.indexOf("request cancelled [fixture-mid-request] at fixture-compiler-stage") >= 0,
			"compiler-stage cancellation should preserve its first observed stage");

		final shutdownReply = CompilationServerRequestDispatcher.dispatch(new CompilationServerRequest(14, [], ["--hxhx-server-control", "shutdown"], null),
			(_, _) -> throw "shutdown must not compile");
		assertTrue(!shutdownReply.isError, "shutdown control should succeed");
		assertTrue(shutdownReply.stopServer, "shutdown control should ask its transport to stop");
		assertTrue(CompilationServerRequestCodec.encodeReply(shutdownReply).indexOf("hxhx_server_control.shutdown=ok") >= 0,
			"shutdown response should confirm the requested control");

		final unknownControlReply = CompilationServerRequestDispatcher.dispatch(new CompilationServerRequest(15, [], ["--hxhx-server-control", "restart"],
			null), (_, _) -> throw "unknown control must not compile");
		assertTrue(unknownControlReply.isError, "unknown server control should fail");
		assertTrue(!unknownControlReply.stopServer, "unknown server control should keep the transport running");

		final stopSignal = new CompilationServerStopSignal();
		stopSignal.record(true);
		assertTrue(stopSignal.take(), "a recorded stop decision should be returned once");
		assertTrue(!stopSignal.take(), "taking a stop decision should clear it for later connections");
		stopSignal.record(false);
		assertTrue(!stopSignal.take(), "recording an ordinary reply should not request shutdown");

		final displayReply = CompilationServerRequestDispatcher.dispatch(decoded, (_, _) -> {
			throw "display request must not invoke the ordinary compile callback";
		});
		assertTrue(!displayReply.isError, "supported display request should not be an error reply");
		assertTrue(CompilationServerRequestCodec.encodeReply(displayReply).indexOf("diagnostics") >= 0,
			"display response should come from the shared dispatcher");

		assertEquals(CompilationServerRequestCodec.encodeSocketReply(reply([new CompilationRequestOutputEvent("plain\n", true)], false)), "plain\n",
			"socket stderr encoding");
		final encodedError = CompilationServerRequestCodec.encodeSocketReply(reply([], true));
		assertEquals(encodedError, "\x02\n", "socket error encoding should use Haxe's error control line");

		MacroState.setDefine("HXHX_STALE_REQUEST_FIXTURE", "old");
		final realFailure = CompilationServerRequestDispatcher.dispatch(new CompilationServerRequest(11, ["--hxhx-no-run", "--hxhx-no-emit"], [], null),
			Stage3Compiler.runRequest);
		final realFailureWire = CompilationServerRequestCodec.encodeReply(realFailure);
		assertTrue(realFailure.isError, "a real Stage3 missing-main request should fail");
		assertTrue(realFailureWire.indexOf("hxhx_macro_runtime_mode=inproc") >= 0, "a real Stage3 request should return normal compiler output to its client");
		assertTrue(realFailureWire.indexOf("missing -main <TypeName>") >= 0, "a real Stage3 request should return its specific diagnostic to its client");
		assertTrue(StringTools.endsWith(realFailureWire, "\x02\n"), "a real Stage3 failure should end with Haxe's failure marker");
		assertTrue(!MacroState.defined("HXHX_STALE_REQUEST_FIXTURE"), "failed request should clear request-global macro state");

		final tmpRoot = ".tmp/m14_compilation_server_request_dispatcher";
		final srcDir = haxe.io.Path.join([tmpRoot, "src"]);
		deleteRecursive(tmpRoot);
		FileSystem.createDirectory(tmpRoot);
		FileSystem.createDirectory(srcDir);
		File.saveContent(haxe.io.Path.join([srcDir, "Main.hx"]), "class Main { static function main():Void {} }\n");
		final realSuccess = CompilationServerRequestDispatcher.dispatch(new CompilationServerRequest(12,
			["--hxhx-no-run", "--hxhx-no-emit", "-cp", srcDir, "-main", "Main"], [], null), Stage3Compiler.runRequest);
		final realSuccessWire = CompilationServerRequestCodec.encodeReply(realSuccess);
		deleteRecursive(tmpRoot);
		assertTrue(!realSuccess.isError, "a real Stage3 no-emit request should succeed");
		assertTrue(realSuccessWire.indexOf("resolved_modules=1") >= 0, "a real successful request should return compiler progress to its client");
		assertTrue(realSuccessWire.indexOf("stage3=no_emit_ok") >= 0, "a real successful request should return its completion marker to its client");
		assertTrue(realSuccessWire.indexOf("\x02") == -1, "a successful request should not contain Haxe's failure marker");
	}
}
