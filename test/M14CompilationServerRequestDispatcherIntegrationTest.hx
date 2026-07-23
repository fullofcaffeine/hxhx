import haxe.io.Bytes;
import backend.EmitArtifact;
import backend.EmitResult;
import HxParser;
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

private class RecordingCompilerSourceProvider {
	public var resolveCalls(default, null):Int = 0;
	public var readCalls(default, null):Int = 0;
	public var parseCalls(default, null):Int = 0;
	public var directoryCalls(default, null):Int = 0;

	final delegate:CompilerSourceProvider;

	public function new() {
		delegate = new CompilerSourceProvider();
	}

	public function provider():CompilerSourceProvider
		return CompilerSourceProvider.fromCallbacks(resolveModule, readSource, parseFilteredSource, readDirectory, isFile, prepareFinish, finish, report);

	public function resolveModule(classPaths:Array<String>, modulePath:String):CompilerModuleResolution {
		resolveCalls += 1;
		return delegate.resolveModule(classPaths, modulePath);
	}

	public function readSource(filePath:String):Null<String> {
		readCalls += 1;
		return delegate.readSource(filePath);
	}

	public function parseFilteredSource(filteredSource:String, filePath:String):ParsedModule {
		parseCalls += 1;
		return delegate.parseFilteredSource(filteredSource, filePath);
	}

	public function readDirectory(path:String):Array<String> {
		directoryCalls += 1;
		return delegate.readDirectory(path);
	}

	public function isFile(path:String):Bool
		return delegate.isFile(path);

	public function prepareFinish(requestSucceeded:Bool):Void
		delegate.prepareFinish(requestSucceeded);

	public function finish(requestSucceeded:Bool):Void
		delegate.finish(requestSucceeded);

	public function report():CompilerSourceProviderReport
		return delegate.report();
}

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

	static function ensureDirectory(path:String):Void {
		if (FileSystem.exists(path))
			return;
		final parent = haxe.io.Path.directory(path);
		if (parent != null && parent.length > 0 && parent != path)
			ensureDirectory(parent);
		FileSystem.createDirectory(path);
	}

	static function containsTransactionPath(path:String):Bool {
		if (!FileSystem.exists(path) || !FileSystem.isDirectory(path))
			return false;
		for (entry in FileSystem.readDirectory(path)) {
			if (StringTools.startsWith(entry, ".hxhx-server-stage-") || StringTools.startsWith(entry, ".hxhx-server-backup-"))
				return true;
			if (containsTransactionPath(haxe.io.Path.join([path, entry])))
				return true;
		}
		return false;
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
		assertTrue(reportWire.indexOf("hxhx_server_report.output_transaction=not_started") >= 0,
			"baseline report should say a request that did not compile never started output staging");
		assertTrue(reportWire.indexOf("hxhx_server_report.phase_count=") >= 0, "baseline report should count its measured phases");
		assertTrue(reportWire.indexOf("hxhx_server_report.phase[0].name=request-init") >= 0, "baseline report should name phases in first-observed order");
		assertTrue(reportWire.indexOf("hxhx_server_report.phase[0].elapsed_ms=") >= 0, "baseline report should include a non-negative duration for each phase");

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
		HxParser.debugBodyLabel = "stale request body";
		final realFailure = CompilationServerRequestDispatcher.dispatch(new CompilationServerRequest(11, ["--hxhx-no-run", "--hxhx-no-emit"], [], null),
			Stage3Compiler.runRequest);
		final realFailureWire = CompilationServerRequestCodec.encodeReply(realFailure);
		assertTrue(realFailure.isError, "a real Stage3 missing-main request should fail");
		assertTrue(realFailureWire.indexOf("hxhx_macro_runtime_mode=inproc") >= 0, "a real Stage3 request should return normal compiler output to its client");
		assertTrue(realFailureWire.indexOf("missing -main <TypeName>") >= 0, "a real Stage3 request should return its specific diagnostic to its client");
		assertTrue(StringTools.endsWith(realFailureWire, "\x02\n"), "a real Stage3 failure should end with Haxe's failure marker");
		assertTrue(!MacroState.defined("HXHX_STALE_REQUEST_FIXTURE"), "failed request should clear request-global macro state");
		assertEquals(HxParser.debugBodyLabel, "", "failed request parser debug state");

		final transactionRoot = ".tmp/m14_compilation_server_output_transaction";
		final finalDirectory = haxe.io.Path.join([transactionRoot, "directory-output"]);
		final finalFileParent = haxe.io.Path.join([transactionRoot, "file-output"]);
		final finalFile = haxe.io.Path.join([finalFileParent, "app.js"]);
		deleteRecursive(transactionRoot);
		ensureDirectory(finalDirectory);
		ensureDirectory(finalFileParent);
		File.saveContent(haxe.io.Path.join([finalDirectory, "old.txt"]), "old directory output");
		File.saveContent(finalFile, "old file output");
		File.saveContent(finalFile + ".map", "old source map");

		final transactionContext = CompilationRequestContext.server(200);
		transactionContext.enableBaselineReport();
		final transactionPaths = transactionContext.prepareOutput(finalDirectory, finalDirectory, finalFile);
		assertTrue(transactionPaths.workingOutDir != transactionPaths.finalOutDir, "server directory output should use a private working path");
		assertTrue(transactionPaths.workingOutputFileHint != transactionPaths.finalOutputFileHint, "server file output should use a private working path");
		ensureDirectory(transactionPaths.workingOutDir);
		File.saveContent(haxe.io.Path.join([transactionPaths.workingOutDir, "new.txt"]), "new directory output");
		final stagedFile = transactionPaths.workingOutputFileHint;
		assertTrue(stagedFile != null, "file transaction should provide a working file path");
		ensureDirectory(haxe.io.Path.directory(stagedFile));
		File.saveContent(stagedFile, "new file output");
		File.saveContent(stagedFile + ".map", "new source map");
		assertEquals(File.getContent(haxe.io.Path.join([finalDirectory, "old.txt"])), "old directory output", "previous directory while output is staged");
		assertEquals(File.getContent(finalFile), "old file output", "previous file while output is staged");
		final finalResult = transactionContext.sealOutput(new EmitResult(stagedFile, [
			new EmitArtifact("entry_js", stagedFile),
			new EmitArtifact("source_map", stagedFile + ".map")
		], false));
		assertEquals(finalResult.entryPath, FileSystem.absolutePath(finalFile), "client entry path after sealing");
		assertEquals(finalResult.artifacts[1].path, FileSystem.absolutePath(finalFile + ".map"), "client sidecar path after sealing");
		assertEquals(File.getContent(finalFile), "old file output", "sealing should not publish before request cleanup");
		transactionContext.registerCleanup("publication-order", () -> {
			assertEquals(File.getContent(finalFile), "old file output", "request cleanup should run before output publication");
		});
		assertTrue(transactionContext.close(), "published output transaction should close cleanly");
		assertTrue(!FileSystem.exists(haxe.io.Path.join([finalDirectory, "old.txt"])), "successful publish should replace the old directory tree");
		assertEquals(File.getContent(haxe.io.Path.join([finalDirectory, "new.txt"])), "new directory output", "published directory output");
		assertEquals(File.getContent(finalFile), "new file output", "published file output");
		assertEquals(File.getContent(finalFile + ".map"), "new source map", "published file sidecar");
		assertTrue(!containsTransactionPath(transactionRoot), "successful publish should leave no staging or backup path");
		assertTrue(transactionContext.output.events()
			.map(event -> event.text)
			.join("")
			.indexOf("hxhx_server_report.output_transaction=committed") >= 0,
			"successful request report should identify committed output");

		final abortDirectory = haxe.io.Path.join([transactionRoot, "abort-output"]);
		ensureDirectory(abortDirectory);
		File.saveContent(haxe.io.Path.join([abortDirectory, "old.txt"]), "keep me");
		final abortContext = CompilationRequestContext.server(201);
		abortContext.enableBaselineReport();
		final abortPaths = abortContext.prepareOutput(abortDirectory, abortDirectory, null);
		ensureDirectory(abortPaths.workingOutDir);
		File.saveContent(haxe.io.Path.join([abortPaths.workingOutDir, "partial.txt"]), "discard me");
		assertTrue(abortContext.close(false), "aborted output transaction should clean its staging tree");
		assertEquals(File.getContent(haxe.io.Path.join([abortDirectory, "old.txt"])), "keep me", "previous output after abort");
		assertTrue(!FileSystem.exists(haxe.io.Path.join([abortDirectory, "partial.txt"])), "aborted request must not publish partial output");
		assertTrue(!containsTransactionPath(transactionRoot), "aborted request should leave no staging or backup path");
		assertTrue(abortContext.output.events()
			.map(event -> event.text)
			.join("")
			.indexOf("hxhx_server_report.output_transaction=aborted") >= 0,
			"aborted request report should identify discarded output");

		final cleanupFailureDirectory = haxe.io.Path.join([transactionRoot, "cleanup-failure-output"]);
		ensureDirectory(cleanupFailureDirectory);
		File.saveContent(haxe.io.Path.join([cleanupFailureDirectory, "old.txt"]), "keep after cleanup failure");
		final cleanupFailureContext = CompilationRequestContext.server(202);
		cleanupFailureContext.enableBaselineReport();
		final cleanupFailurePaths = cleanupFailureContext.prepareOutput(cleanupFailureDirectory, cleanupFailureDirectory, null);
		ensureDirectory(cleanupFailurePaths.workingOutDir);
		final cleanupFailureStagedFile = haxe.io.Path.join([cleanupFailurePaths.workingOutDir, "new.txt"]);
		File.saveContent(cleanupFailureStagedFile, "must not publish");
		cleanupFailureContext.sealOutput(new EmitResult(cleanupFailureStagedFile, [new EmitArtifact("generated", cleanupFailureStagedFile)], false));
		cleanupFailureContext.registerCleanup("deliberate-fixture-failure", () -> throw "cleanup failed for fixture");
		assertTrue(!cleanupFailureContext.close(true), "cleanup failure should fail the request and prevent output publication");
		assertEquals(File.getContent(haxe.io.Path.join([cleanupFailureDirectory, "old.txt"])), "keep after cleanup failure",
			"previous output after cleanup failure");
		assertTrue(!FileSystem.exists(haxe.io.Path.join([cleanupFailureDirectory, "new.txt"])), "cleanup failure must not publish staged output");
		final cleanupFailureReport = cleanupFailureContext.output.events().map(event -> event.text).join("");
		assertTrue(cleanupFailureReport.indexOf("request cleanup failed [deliberate-fixture-failure]") >= 0, "cleanup failure should name the failing cleanup");
		assertTrue(cleanupFailureReport.indexOf("hxhx_server_report.output_transaction=aborted") >= 0,
			"cleanup failure report should identify discarded output");
		assertTrue(!containsTransactionPath(transactionRoot), "cleanup failure should leave no staging or backup path");

		final escapedOutputContext = CompilationRequestContext.server(203);
		final escapedOutputPaths = escapedOutputContext.prepareOutput(haxe.io.Path.join([transactionRoot, "escaped-output"]),
			haxe.io.Path.join([transactionRoot, "escaped-output"]), null);
		ensureDirectory(escapedOutputPaths.workingOutDir);
		final escapedPath = haxe.io.Path.join([transactionRoot, "outside-staging.txt"]);
		var escapedOutputRejected = false;
		try {
			escapedOutputContext.sealOutput(new EmitResult(escapedPath, [new EmitArtifact("escaped", escapedPath)], false));
		} catch (error:String) {
			escapedOutputRejected = error.indexOf("outside request staging") >= 0;
		}
		assertTrue(escapedOutputRejected, "server output outside private staging should fail before publication");
		assertTrue(escapedOutputContext.close(false), "rejected escaped output should abort its staging tree cleanly");
		assertTrue(!containsTransactionPath(transactionRoot), "rejected escaped output should leave no staging or backup path");
		deleteRecursive(transactionRoot);

		final tmpRoot = ".tmp/m14_compilation_server_request_dispatcher";
		final srcDir = haxe.io.Path.join([tmpRoot, "src"]);
		deleteRecursive(tmpRoot);
		FileSystem.createDirectory(tmpRoot);
		FileSystem.createDirectory(srcDir);
		final mainPath = haxe.io.Path.join([srcDir, "Main.hx"]);
		final sourceA = "class Main { static function main():Void {} }\n";
		File.saveContent(mainPath, sourceA);
		final recordingSources = new RecordingCompilerSourceProvider();
		final sourceOwnedContext = new CompilationRequestContext(0, true, false, recordingSources.provider());
		final sourceOwnedCode = Stage3Compiler.runRequest(["--hxhx-no-run", "--hxhx-no-emit", "-cp", srcDir, "-main", "Main"], sourceOwnedContext);
		assertTrue(sourceOwnedContext.close(sourceOwnedCode == 0), "source-provider request should clean up");
		assertTrue(sourceOwnedCode == 0, "source-provider request should compile");
		assertTrue(recordingSources.resolveCalls > 0, "Stage3 resolution should use the request-owned source provider");
		assertTrue(recordingSources.readCalls > 0, "Stage3 source reads should use the request-owned source provider");
		assertTrue(recordingSources.parseCalls > 0, "Stage3 parsing should use the request-owned source provider");
		final realSuccess = CompilationServerRequestDispatcher.dispatch(new CompilationServerRequest(12,
			["--hxhx-no-run", "--hxhx-no-emit", "-cp", srcDir, "-main", "Main"], [], null), Stage3Compiler.runRequest);
		final realSuccessWire = CompilationServerRequestCodec.encodeReply(realSuccess);
		assertTrue(!realSuccess.isError, "a real Stage3 no-emit request should succeed");
		assertTrue(realSuccessWire.indexOf("resolved_modules=1") >= 0, "a real successful request should return compiler progress to its client");
		assertTrue(realSuccessWire.indexOf("stage3=no_emit_ok") >= 0, "a real successful request should return its completion marker to its client");
		assertTrue(realSuccessWire.indexOf("\x02") == -1, "a successful request should not contain Haxe's failure marker");

		final realArtifact = haxe.io.Path.join([tmpRoot, "out", "main.js"]);
		final realEmit = CompilationServerRequestDispatcher.dispatch(new CompilationServerRequest(13, [
			"--hxhx-no-run",
			"--hxhx-server-report",
			"--hxhx-backend",
			"js-native",
			"--js",
			realArtifact,
			"-cp",
			srcDir,
			"-main",
			"Main"
		], [], null), Stage3Compiler.runRequest);
		final realEmitWire = CompilationServerRequestCodec.encodeReply(realEmit);
		assertTrue(!realEmit.isError, "a real Stage3 server emission should publish successfully");
		assertTrue(FileSystem.exists(realArtifact), "a real Stage3 server emission should publish its requested target file: " + realEmitWire);
		assertTrue(FileSystem.exists(realArtifact + ".map"), "a real Stage3 server emission should publish its target sidecar");
		assertTrue(realEmitWire.indexOf("hxhx_server_report.output_transaction=committed") >= 0, "a real emitted request should report committed output");
		assertTrue(realEmitWire.indexOf(".hxhx-server-stage-") == -1, "private staging names must not reach compiler output");
		final realArtifactBeforeFailure = File.getContent(realArtifact);

		final realEmitFailure = CompilationServerRequestDispatcher.dispatch(new CompilationServerRequest(14, [
			"--hxhx-no-run",
			"--hxhx-server-report",
			"--hxhx-backend",
			"js-native",
			"--js",
			realArtifact,
			"-cp",
			srcDir,
			"-main",
			"MissingMain"
		], [], null), Stage3Compiler.runRequest);
		final realEmitFailureWire = CompilationServerRequestCodec.encodeReply(realEmitFailure);
		assertTrue(realEmitFailure.isError, "a real Stage3 failure should not publish staged output");
		assertEquals(File.getContent(realArtifact), realArtifactBeforeFailure, "last good target after a failed request");
		assertTrue(realEmitFailureWire.indexOf("hxhx_server_report.output_transaction=aborted") >= 0, "failed emitted request should report aborted output");
		assertTrue(!containsTransactionPath(tmpRoot), "real Stage3 requests should leave no transaction staging or backup path");

		function proveTargetFailureRecovery(label:String, requestId:Int, targetArgs:Array<String>, generatedPath:String):Void {
			final directContext = new CompilationRequestContext(0, true, false);
			final directCode = Stage3Compiler.runRequest(targetArgs, directContext);
			assertTrue(directContext.close(directCode == 0), label + " direct request should clean up");
			assertTrue(directCode == 0, label + " direct request should compile");
			assertTrue(FileSystem.exists(generatedPath), label + " direct request should create its target source");
			final directBytes = File.getBytes(generatedPath);

			final firstServer = CompilationServerRequestDispatcher.dispatch(new CompilationServerRequest(requestId, targetArgs, [], null),
				Stage3Compiler.runRequest);
			assertTrue(!firstServer.isError, label + " first server request should compile");
			assertTrue(FileSystem.exists(generatedPath), label + " first server request should publish its target source");
			assertTrue(File.getBytes(generatedPath).compare(directBytes) == 0, label + " direct and first server target bytes should match");

			final failedArgs = targetArgs.copy();
			final mainIndex = failedArgs.indexOf("Main");
			assertTrue(mainIndex >= 0, label + " fixture should contain its main type");
			failedArgs[mainIndex] = "MissingMain";
			final failedServer = CompilationServerRequestDispatcher.dispatch(new CompilationServerRequest(requestId + 1, failedArgs, [], null),
				Stage3Compiler.runRequest);
			assertTrue(failedServer.isError, label + " missing-main server request should fail");
			assertTrue(File.getBytes(generatedPath).compare(directBytes) == 0, label + " failed request should retain the last good target bytes");

			final repeatedServer = CompilationServerRequestDispatcher.dispatch(new CompilationServerRequest(requestId + 2, targetArgs, [], null),
				Stage3Compiler.runRequest);
			assertTrue(!repeatedServer.isError, label + " repeated server request should recover");
			assertTrue(File.getBytes(generatedPath).compare(directBytes) == 0, label + " repeated server target bytes should match a direct request");
		}

		final phpRoot = haxe.io.Path.join([tmpRoot, "php"]);
		final phpOutputDir = haxe.io.Path.join([phpRoot, "output"]);
		final phpOutput = haxe.io.Path.join([phpOutputDir, "index.php"]);
		proveTargetFailureRecovery("PHP", 300, [
			"--hxhx-no-run",
			"--hxhx-backend",
			"php-native",
			"--hxhx-out",
			haxe.io.Path.join([phpRoot, "work"]),
			"--php",
			phpOutputDir,
			"-cp",
			srcDir,
			"-main",
			"Main"
		], phpOutput);

		final cppRoot = haxe.io.Path.join([tmpRoot, "cpp"]);
		final cppOutput = haxe.io.Path.join([cppRoot, "src", "Main.cpp"]);
		proveTargetFailureRecovery("C++", 310, [
			"--hxhx-no-run",
			"--hxhx-backend",
			"cpp-native",
			"--hxhx-out",
			cppRoot,
			"--cpp",
			cppRoot,
			"-D",
			"no-compilation",
			"-cp",
			srcDir,
			"-main",
			"Main"
		], cppOutput);
		assertTrue(!containsTransactionPath(tmpRoot), "cross-target requests should leave no transaction staging or backup path");
		deleteRecursive(tmpRoot);
	}
}
