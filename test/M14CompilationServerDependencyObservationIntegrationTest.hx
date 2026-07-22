import backend.EmitArtifact;
import backend.EmitResult;
import hxhx.CompilationServerDependencyCatalog;
import hxhx.CompilationServerReply;
import hxhx.CompilationServerRequest;
import hxhx.CompilationServerRequestCodec;
import hxhx.CompilationServerRequestDispatcher;
import hxhx.CompilationServerSourceCache;
import hxhx.Stage3Compiler;
import sys.FileSystem;
import sys.io.File;

/**
	Exercises dependency observation through complete native server requests.

	Typing still runs on every request. The test proves only that successful clean
	compilations publish deterministic observations, explain ordinary versus public
	changes, and discard failed or reset history before typed caching is enabled.
**/
class M14CompilationServerDependencyObservationIntegrationTest {
	static var nextRequestId:Int = 4000;

	static function assertTrue(condition:Bool, message:String):Void {
		if (!condition)
			throw message;
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

	static function compile(sourceCache:CompilationServerSourceCache, dependencyCatalog:CompilationServerDependencyCatalog, args:Array<String>,
			?requestFlags:Array<String>):CompilationServerReply {
		nextRequestId += 1;
		return CompilationServerRequestDispatcher.dispatch(new CompilationServerRequest(nextRequestId, args, requestFlags == null ? [] : requestFlags, null),
			Stage3Compiler.runRequest, sourceCache, dependencyCatalog);
	}

	static function wire(reply:CompilationServerReply):String
		return CompilationServerRequestCodec.encodeReply(reply);

	static function reportInt(result:String, key:String):Int {
		final marker = key + "=";
		final start = result.indexOf(marker);
		assertTrue(start >= 0, "server report should contain " + key);
		var end = start + marker.length;
		while (end < result.length) {
			final code = result.charCodeAt(end);
			if (code < 48 || code > 57)
				break;
			end += 1;
		}
		final value = Std.parseInt(result.substring(start + marker.length, end));
		assertTrue(value != null, "server report should contain an integer for " + key);
		return value;
	}

	static function apiSource(returnType:String, bodyValue:String):String {
		return [
			"class Api {",
			'  public static function answer():$returnType return $bodyValue;',
			"}"
		].join("\n");
	}

	/** A failed request must leave the previous successful observation visible. **/
	static function verifyFailedPublication(catalog:CompilationServerDependencyCatalog):Void {
		final revisionA = new CompilerTypedModuleRevision("FailureContract", "public-a", "implementation-a");
		final revisionB = new CompilerTypedModuleRevision("FailureContract", "public-b", "implementation-b");
		final snapshotA = new CompilerDependencySnapshot([revisionA], []);
		final snapshotB = new CompilerDependencySnapshot([revisionB], []);
		final seed = catalog.openRequest(["failure-contract"]);
		seed.record(snapshotA);
		seed.finish(true);
		final failed = catalog.openRequest(["failure-contract"]);
		failed.record(snapshotB);
		failed.finish(false);
		final probe = catalog.openRequest(["failure-contract"]);
		probe.record(snapshotA);
		assertTrue(probe.report().hasPrevious, "probe should retain the last successful dependency snapshot");
		final comparison = probe.report().comparison;
		assertTrue(comparison != null
			&& comparison.getInvalidations().length == 0, "failed dependency request must not replace the successful snapshot");
		probe.finish(false);
	}

	/** Generated output must become visible before dependency history may publish. **/
	static function verifyOutputFailurePublication(catalog:CompilationServerDependencyCatalog, root:String):Void {
		final invocation = ["dependency-output-failure-contract"];
		final snapshotA = new CompilerDependencySnapshot([new CompilerTypedModuleRevision("OutputFailure", "public-a", "implementation-a")], []);
		final snapshotB = new CompilerDependencySnapshot([new CompilerTypedModuleRevision("OutputFailure", "public-b", "implementation-b")], []);
		final seed = catalog.openRequest(invocation);
		seed.record(snapshotA);
		seed.finish(true);

		nextRequestId += 1;
		final failedRequest = catalog.openRequest(invocation);
		final context = hxhx.CompilationRequestContext.server(nextRequestId, null, failedRequest);
		failedRequest.record(snapshotB);
		final finalOutput = haxe.io.Path.join([root, "dependency-output-failure-result"]);
		final paths = context.prepareOutput(finalOutput, finalOutput, null);
		ensureDirectory(haxe.io.Path.directory(paths.workingOutDir));
		File.saveContent(paths.workingOutDir, "this file deliberately prevents directory publication");
		final stagedEntry = haxe.io.Path.join([paths.workingOutDir, "main.js"]);
		context.sealOutput(new EmitResult(stagedEntry, [new EmitArtifact("entry_js", stagedEntry)], false));
		assertTrue(!context.close(true), "output-publication failure should fail dependency observation publication");

		final probe = catalog.openRequest(invocation);
		probe.record(snapshotA);
		final comparison = probe.report().comparison;
		assertTrue(comparison != null && comparison.getInvalidations().length == 0,
			"failed output must leave the earlier successful dependency snapshot intact");
		probe.finish(false);
	}

	/** Invocation variants must not grow retained observation history without a bound. **/
	static function verifyBoundedInvocationHistory():Void {
		final catalog = new CompilationServerDependencyCatalog(2);
		for (name in ["a", "b", "c"]) {
			final request = catalog.openRequest([name]);
			request.record(new CompilerDependencySnapshot([new CompilerTypedModuleRevision(name, "public", "implementation")], []));
			request.finish(true);
		}
		final evictedProbe = catalog.openRequest(["a"]);
		evictedProbe.record(new CompilerDependencySnapshot([new CompilerTypedModuleRevision("a", "public", "implementation")], []));
		assertTrue(!evictedProbe.report().hasPrevious, "the oldest invocation history should be evicted at the configured bound");
		evictedProbe.finish(false);

		var missingSnapshotRejected = false;
		try {
			final missingSnapshot = catalog.openRequest(["missing-snapshot"]);
			missingSnapshot.requireSnapshot();
			missingSnapshot.finish(true);
		} catch (_) {
			missingSnapshotRejected = true;
		}
		assertTrue(missingSnapshotRejected, "a successful report-enabled request must not silently omit its typed-program observation");

		final controlRequest = catalog.openRequest(["control-request"]);
		controlRequest.finish(true);
		final controlProbe = catalog.openRequest(["control-request"]);
		assertTrue(!controlProbe.report().hasPrevious, "a successful control/display request must not publish empty dependency history");
		controlProbe.finish(false);
	}

	static function main():Void {
		final root = ".tmp/m14_compilation_server_dependency_observation";
		deleteRecursive(root);
		ensureDirectory(root);
		final apiPath = haxe.io.Path.join([root, "Api.hx"]);
		final mainPath = haxe.io.Path.join([root, "Main.hx"]);
		File.saveContent(apiPath, apiSource("Int", "42"));
		File.saveContent(mainPath, [
			"import Api;",
			"class Main {",
			"  public static function main():Void {",
			"    var answer:Int = Api.answer();",
			"  }",
			"}"
		].join("\n"));
		final args = [
			"--hxhx-no-run",
			"--hxhx-no-emit",
			"--hxhx-server-report",
			"-cp",
			root,
			"-main",
			"Main"
		];
		final sourceCache = new CompilationServerSourceCache();
		final dependencyCatalog = new CompilationServerDependencyCatalog();
		verifyBoundedInvocationHistory();

		var failure:Null<String> = null;
		try {
			final withoutReportArgs = args.filter(argument -> argument != "--hxhx-server-report");
			final withoutReport = wire(compile(sourceCache, dependencyCatalog, withoutReportArgs));
			assertTrue(withoutReport.indexOf("hxhx_server_report.dependency_observation") == -1,
				"ordinary server requests should not pay for or publish dependency observation");

			final commandOnlyReply = compile(sourceCache, dependencyCatalog, [
				"--hxhx-no-run",
				"--hxhx-no-emit",
				"--hxhx-server-report",
				"--cmd",
				"unsupported command-only fixture"
			]);
			assertTrue(!commandOnlyReply.isError, "a successful request without compiler roots should not promise a typed-program snapshot");
			final commandOnly = wire(commandOnlyReply);
			assertTrue(reportInt(commandOnly, "hxhx_server_report.dependency_modules") == 0,
				"a successful request without compiler roots should publish no dependency modules");

			final cold = compile(sourceCache, dependencyCatalog, args);
			final coldWire = wire(cold);
			assertTrue(!cold.isError, "cold dependency-observation request should compile");
			assertTrue(coldWire.indexOf("hxhx_server_report.dependency_observation=enabled") >= 0, "server should identify dependency observation mode");
			assertTrue(reportInt(coldWire, "hxhx_server_report.dependency_previous_snapshot") == 0, "cold request should have no prior successful observation");
			assertTrue(reportInt(coldWire, "hxhx_server_report.dependency_modules") == 2, "cold request should observe both typed modules");
			assertTrue(reportInt(coldWire, "hxhx_server_report.dependency_edges") > 0, "cold request should observe the Main-to-Api dependency");

			final warmWire = wire(compile(sourceCache, dependencyCatalog, args));
			assertTrue(reportInt(warmWire, "hxhx_server_report.dependency_previous_snapshot") == 1,
				"warm request should compare with the last successful observation");
			assertTrue(reportInt(warmWire, "hxhx_server_report.dependency_public_changes") == 0, "unchanged request should report no public-interface changes");
			assertTrue(reportInt(warmWire, "hxhx_server_report.dependency_implementation_changes") == 0,
				"unchanged request should report no implementation changes");
			assertTrue(reportInt(warmWire, "hxhx_server_report.dependency_predicted_invalidations") == 0, "unchanged request should predict no invalidations");

			File.saveContent(apiPath, apiSource("Int", "43"));
			final bodyChangeWire = wire(compile(sourceCache, dependencyCatalog, args));
			assertTrue(reportInt(bodyChangeWire, "hxhx_server_report.dependency_public_changes") == 0,
				"ordinary body edit should preserve Api's public interface");
			assertTrue(reportInt(bodyChangeWire, "hxhx_server_report.dependency_implementation_changes") == 1,
				"ordinary body edit should change only Api's implementation revision");
			assertTrue(reportInt(bodyChangeWire, "hxhx_server_report.dependency_predicted_invalidations") == 1,
				"ordinary body edit should predict only the edited module");
			assertTrue(bodyChangeWire.indexOf(".module=Api") >= 0 && bodyChangeWire.indexOf(".module=Main") == -1,
				"ordinary body edit should not invalidate a signature-only caller");

			File.saveContent(apiPath, apiSource("String", '"changed"'));
			final signatureWire = wire(compile(sourceCache, dependencyCatalog, args));
			assertTrue(reportInt(signatureWire, "hxhx_server_report.dependency_public_changes") == 1, "return-type edit should change Api's public interface");
			assertTrue(signatureWire.indexOf(".module=Main") >= 0, "public-interface edit should predict that Main must be checked again");

			verifyFailedPublication(dependencyCatalog);
			verifyOutputFailurePublication(dependencyCatalog, root);

			final reset = compile(sourceCache, dependencyCatalog, [], ["--hxhx-server-control", "reset"]);
			assertTrue(!reset.isError, "reset should clear source and dependency observations");
			final afterResetWire = wire(compile(sourceCache, dependencyCatalog, args));
			assertTrue(reportInt(afterResetWire, "hxhx_server_report.dependency_previous_snapshot") == 0,
				"reset should make dependency observation cold again");
		} catch (error:haxe.Exception) {
			failure = error.message;
		} catch (error:String) {
			failure = error;
		}
		deleteRecursive(root);
		if (failure != null)
			throw failure;
		Sys.println("COMPILATION_SERVER_DEPENDENCY_OBSERVATION:PASS");
	}
}
