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

	static function reportValue(result:String, key:String):String {
		final marker = key + "=";
		final start = result.indexOf(marker);
		assertTrue(start >= 0, "server report should contain " + key);
		final valueStart = start + marker.length;
		var end = result.indexOf("\n", valueStart);
		if (end < 0)
			end = result.length;
		return StringTools.trim(result.substring(valueStart, end));
	}

	static function countOccurrences(value:String, needle:String):Int {
		if (value == null || needle == null || needle.length == 0)
			return 0;
		var count = 0;
		var offset = 0;
		while (true) {
			final found = value.indexOf(needle, offset);
			if (found < 0)
				return count;
			count += 1;
			offset = found + needle.length;
		}
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

	/** Prove that the real wait-server path retains class-path origin without reporting host paths. **/
	static function verifySourceOriginShadowing(root:String):Void {
		final shadowRoot = haxe.io.Path.join([root, "origin-shadowing"]);
		final high = haxe.io.Path.join([shadowRoot, "high"]);
		final low = haxe.io.Path.join([shadowRoot, "low"]);
		ensureDirectory(high);
		ensureDirectory(low);
		final lowApi = haxe.io.Path.join([low, "Api.hx"]);
		final highApi = haxe.io.Path.join([high, "Api.hx"]);
		File.saveContent(lowApi, apiSource("Int", "42"));
		File.saveContent(haxe.io.Path.join([low, "Main.hx"]),
			"import Api; class Main { public static function main():Void { var answer:Dynamic = Api.answer(); } }");
		final args = [
			"--hxhx-no-run",
			"--hxhx-no-emit",
			"--hxhx-server-report",
			"-cp",
			high,
			"-cp",
			low,
			"-main",
			"Main"
		];
		final sourceCache = new CompilationServerSourceCache();
		final dependencyCatalog = new CompilationServerDependencyCatalog();
		final lowerWire = wire(compile(sourceCache, dependencyCatalog, args));
		final lowerSnapshot = reportValue(lowerWire, "hxhx_server_report.dependency_snapshot");

		File.saveContent(highApi, apiSource("Int", "42"));
		final equalBytesShadowWire = wire(compile(sourceCache, dependencyCatalog, args));
		assertTrue(reportInt(equalBytesShadowWire, "hxhx_server_report.dependency_source_origin_changes") == 1,
			"an equal-byte higher-priority provider should still change Api's source origin");
		assertTrue(reportInt(equalBytesShadowWire, "hxhx_server_report.dependency_public_changes") == 0
			&& reportInt(equalBytesShadowWire, "hxhx_server_report.dependency_implementation_changes") == 0,
			"equal bytes from a different origin should not pretend the Haxe interface or implementation changed");
		assertTrue(reportInt(equalBytesShadowWire, "hxhx_server_report.dependency_predicted_invalidations") == 1
			&& equalBytesShadowWire.indexOf("source-origin-changed:Api:Api@classpath[1]->Api@classpath[0]") >= 0,
			"origin-only replacement should recheck Api and explain the path-safe class-path change");
		assertTrue(equalBytesShadowWire.indexOf(shadowRoot) < 0, "ordinary dependency reports must not include the temporary workspace path");

		File.saveContent(highApi, apiSource("String", '"higher"'));
		final changedShadowWire = wire(compile(sourceCache, dependencyCatalog, args));
		assertTrue(reportInt(changedShadowWire, "hxhx_server_report.dependency_public_changes") == 1
			&& changedShadowWire.indexOf(".module=Main") >= 0,
			"a public change in the selected provider should continue through Main's real dependency edge");

		FileSystem.rename(highApi, haxe.io.Path.join([high, "MovedApi.hx"]));
		final restoredWire = wire(compile(sourceCache, dependencyCatalog, args));
		assertTrue(reportInt(restoredWire, "hxhx_server_report.dependency_source_origin_changes") == 1,
			"renaming the higher-priority source away should restore the lower provider");
		assertTrue(reportValue(restoredWire, "hxhx_server_report.dependency_snapshot") == lowerSnapshot,
			"returning to the original source and origin should reproduce the original snapshot fingerprint");
	}

	/** Prove that a new direct module file replaces secondary-type fallback safely. **/
	static function verifySecondaryTypeReplacement(root:String):Void {
		final sourceRoot = haxe.io.Path.join([root, "origin-secondary-type"]);
		final packageRoot = haxe.io.Path.join([sourceRoot, "pack"]);
		final directModuleRoot = haxe.io.Path.join([packageRoot, "Mod"]);
		ensureDirectory(packageRoot);
		File.saveContent(haxe.io.Path.join([packageRoot, "Mod.hx"]), [
			"package pack;",
			"class Mod {}",
			"class SubType { public static function value():Int return 7; }"
		].join("\n"));
		File.saveContent(haxe.io.Path.join([sourceRoot, "Main.hx"]),
			"import pack.Mod.SubType; class Main { public static function main():Void { var value:Dynamic = SubType.value(); } }");
		final args = [
			"--hxhx-no-run",
			"--hxhx-no-emit",
			"--hxhx-server-report",
			"-cp",
			sourceRoot,
			"-main",
			"Main"
		];
		final sourceCache = new CompilationServerSourceCache();
		final dependencyCatalog = new CompilationServerDependencyCatalog();
		final fallbackReply = compile(sourceCache, dependencyCatalog, args);
		assertTrue(!fallbackReply.isError, "secondary-type fallback should compile before a direct file exists");
		final fallbackWire = wire(fallbackReply);
		final fallbackSnapshot = reportValue(fallbackWire, "hxhx_server_report.dependency_snapshot");

		ensureDirectory(directModuleRoot);
		final directPath = haxe.io.Path.join([directModuleRoot, "SubType.hx"]);
		File.saveContent(directPath, 'package pack.Mod; class SubType { public static function value():String return "direct"; }');
		final directReply = compile(sourceCache, dependencyCatalog, args);
		assertTrue(!directReply.isError, "direct module should compile after replacing secondary-type fallback");
		final directWire = wire(directReply);
		assertTrue(reportInt(directWire, "hxhx_server_report.dependency_source_origin_changes") > 0,
			"adding the direct module should report that module lookup selected a different source");
		assertTrue(directWire.indexOf("source-origin-changed:") >= 0 && directWire.indexOf(".module=Main") >= 0,
			"the direct-file replacement should name its direct origin cause and recheck the caller through a dependency edge");
		assertTrue(directWire.indexOf(sourceRoot) < 0,
			"the secondary-to-direct report should identify logical modules without exposing the temporary workspace path");

		FileSystem.deleteFile(directPath);
		final restoredReply = compile(sourceCache, dependencyCatalog, args);
		assertTrue(!restoredReply.isError, "secondary-type fallback should compile after removing the direct module");
		final restoredWire = wire(restoredReply);
		assertTrue(reportValue(restoredWire, "hxhx_server_report.dependency_snapshot") == fallbackSnapshot,
			"removing the direct file should restore the exact secondary-type snapshot");
	}

	/**
		Prove that evaluated `#if` inputs are tracked without making all defines parser inputs.

		The request always names the same hxml file, while the test edits that file's
		defines. This models a long-lived editor/build-server invocation whose project
		configuration changes between requests.
	**/
	static function verifyConditionalCompilation(root:String):Void {
		final conditionalRoot = haxe.io.Path.join([root, "conditional-compilation"]);
		ensureDirectory(conditionalRoot);
		final absoluteConditionalRoot = FileSystem.absolutePath(conditionalRoot);
		final apiPath = haxe.io.Path.join([conditionalRoot, "Api.hx"]);
		final hxmlPath = haxe.io.Path.join([conditionalRoot, "build.hxml"]);
		File.saveContent(apiPath, [
			"class Api {",
			"  #if enabled",
			"  public static function answer():Int return 42;",
			"  #else",
			'  public static function answer():String return "fallback";',
			"  #end",
			"}"
		].join("\n"));
		File.saveContent(haxe.io.Path.join([conditionalRoot, "Main.hx"]),
			"class Main { public static function main():Void { var answer:Dynamic = Api.answer(); } }");
		final args = ["--hxhx-no-run", "--hxhx-no-emit", "--hxhx-server-report", hxmlPath];
		final sourceCache = new CompilationServerSourceCache();
		final dependencyCatalog = new CompilationServerDependencyCatalog();
		function writeBuild(enabled:Bool, unrelatedValue:String):Void {
			final lines = ["-cp " + absoluteConditionalRoot, "-main Main", "-D unrelated=" + unrelatedValue];
			if (enabled)
				lines.push("-D enabled=private-enabled-value");
			File.saveContent(hxmlPath, lines.join("\n") + "\n");
		}

		writeBuild(true, "private-unrelated-a");
		final firstReply = compile(sourceCache, dependencyCatalog, args);
		final firstWire = wire(firstReply);
		assertTrue(!firstReply.isError, "conditional-compilation baseline should compile: " + firstWire);
		final firstSnapshot = reportValue(firstWire, "hxhx_server_report.dependency_snapshot");

		writeBuild(true, "private-unrelated-b");
		final unrelatedWire = wire(compile(sourceCache, dependencyCatalog, args));
		assertTrue(reportInt(unrelatedWire, "hxhx_server_report.parser_hits") > 0,
			"changing a define that no conditional expression reads should keep matching parser results reusable");
		assertTrue(reportInt(unrelatedWire, "hxhx_server_report.dependency_conditional_compilation_changes") == 0,
			"an unrelated define should not pretend that an evaluated compile-time choice changed");
		assertTrue(reportInt(unrelatedWire, "hxhx_server_report.dependency_program_configuration_changes") == 1
			&& unrelatedWire.indexOf("dependency_program_configuration_change[0].name=define:unrelated") >= 0,
			"the request-wide observer should still name the define because later macro or feature work may inspect it");
		assertTrue(reportInt(unrelatedWire, "hxhx_server_report.dependency_predicted_invalidations") == 2,
			"configuration observation should conservatively recheck every current typed module");
		assertTrue(unrelatedWire.indexOf("private-unrelated-a") < 0 && unrelatedWire.indexOf("private-unrelated-b") < 0,
			"the request-wide configuration report must not reveal either define value");

		writeBuild(false, "private-unrelated-b");
		final changedWire = wire(compile(sourceCache, dependencyCatalog, args));
		assertTrue(reportInt(changedWire, "hxhx_server_report.dependency_conditional_compilation_changes") == 1,
			"changing an evaluated define should identify one conditionally compiled module");
		assertTrue(reportInt(changedWire, "hxhx_server_report.dependency_public_changes") == 1,
			"selecting the other Api branch should report its changed public return type");
		assertTrue(changedWire.indexOf("conditional-compilation-changed:Api:enabled") >= 0 && changedWire.indexOf(".module=Main") >= 0,
			"the server should explain the define key and recheck the caller through Api's public dependency");
		assertTrue(changedWire.indexOf("private-enabled-value") < 0
			&& changedWire.indexOf("private-unrelated-a") < 0
			&& changedWire.indexOf("private-unrelated-b") < 0,
			"ordinary reports must never reveal raw define values");
		assertTrue(changedWire.indexOf(conditionalRoot) < 0, "ordinary conditional-compilation reports must not expose the workspace path");

		writeBuild(true, "private-unrelated-a");
		final restoredReply = compile(sourceCache, dependencyCatalog, args);
		assertTrue(!restoredReply.isError, "restored conditional-compilation baseline should compile");
		final restoredWire = wire(restoredReply);
		assertTrue(reportValue(restoredWire, "hxhx_server_report.dependency_snapshot") == firstSnapshot,
			"returning to exact conditional revision A should reproduce the original typed-program observation");
	}

	/** Prove that real build-macro output is a direct, privacy-safe dependency input. **/
	static function verifyGeneratedDeclarations(root:String):Void {
		final generatedRoot = haxe.io.Path.join([root, "generated-declarations"]);
		ensureDirectory(generatedRoot);
		final hxmlPath = haxe.io.Path.join([generatedRoot, "build.hxml"]);
		File.saveContent(haxe.io.Path.join([generatedRoot, "Api.hx"]), [
			"@:build(hxhxmacros.BuildFieldMacros.addGeneratedField())",
			"class Api { public static function main():Void {} }"
		].join("\n"));
		final args = [
			"--hxhx-no-run",
			"--hxhx-no-emit",
			"--hxhx-server-report",
			"--hxhx-macro-runtime",
			"inproc",
			hxmlPath
		];
		final sourceCache = new CompilationServerSourceCache();
		final dependencyCatalog = new CompilationServerDependencyCatalog();
		function writeBuild(variant:String):Void {
			File.saveContent(hxmlPath, ["-cp .", "-main Api", "-D HXHX_BUILD_VARIANT=" + variant].join("\n") + "\n");
		}

		writeBuild("int");
		final firstReply = compile(sourceCache, dependencyCatalog, args);
		final firstWire = wire(firstReply);
		assertTrue(!firstReply.isError, "generated-declaration baseline should compile: " + firstWire);
		final firstSnapshot = reportValue(firstWire, "hxhx_server_report.dependency_snapshot");

		writeBuild("int-body");
		final bodyReply = compile(sourceCache, dependencyCatalog, args);
		final bodyWire = wire(bodyReply);
		assertTrue(!bodyReply.isError, "generated implementation-only edit should compile: " + bodyWire);
		assertTrue(reportInt(bodyWire, "hxhx_server_report.dependency_generated_declaration_changes") == 1,
			"changing build-macro output should identify the annotated module even when Api.hx is unchanged");
		assertTrue(reportInt(bodyWire, "hxhx_server_report.dependency_public_changes") == 0
			&& reportInt(bodyWire, "hxhx_server_report.dependency_implementation_changes") == 1,
			"changing only a generated function body should preserve its public interface");
		assertTrue(reportInt(bodyWire, "hxhx_server_report.dependency_predicted_invalidations") == 1
			&& bodyWire.indexOf(".module=Api") >= 0,
			"a generated body-only change should recheck Api without inventing another affected module");
		assertTrue(bodyWire.indexOf("generated-declarations-changed:Api") >= 0, "the server should explain that Api's generated declarations changed");

		writeBuild("string");
		final publicReply = compile(sourceCache, dependencyCatalog, args);
		final publicWire = wire(publicReply);
		final publicDependencyReport = publicWire.split("\n").filter(line -> line.indexOf("hxhx_server_report.dependency_") >= 0).join("\n");
		assertTrue(!publicReply.isError, "generated public-interface edit should compile: " + publicWire);
		assertTrue(reportInt(publicWire, "hxhx_server_report.dependency_generated_declaration_changes") == 1
			&& reportInt(publicWire, "hxhx_server_report.dependency_public_changes") == 1,
			"changing a generated return type should report both the macro result and public interface change");
		assertTrue(publicWire.indexOf("generated-declarations-changed:Api") >= 0,
			"a generated public signature change should identify the annotated module as the direct cause");
		assertTrue(publicDependencyReport.indexOf("private-generated-value") < 0,
			"the dependency report must not expose the generated member's private source text");
		assertTrue(publicDependencyReport.indexOf(FileSystem.absolutePath(generatedRoot)) < 0,
			"the generated-declaration report must not expose an absolute workspace path");

		writeBuild("int");
		final restoredReply = compile(sourceCache, dependencyCatalog, args);
		assertTrue(!restoredReply.isError, "restored generated-declaration baseline should compile");
		assertTrue(reportValue(wire(restoredReply), "hxhx_server_report.dependency_snapshot") == firstSnapshot,
			"returning to exact generated result A should reproduce the original dependency snapshot");
	}

	/** Prove that the public report preserves body-sensitive static initialization. **/
	static function verifyStaticInitialization(root:String):Void {
		final staticRoot = haxe.io.Path.join([root, "static-initialization"]);
		ensureDirectory(staticRoot);
		final apiPath = haxe.io.Path.join([staticRoot, "InitApi.hx"]);
		File.saveContent(apiPath, "class InitApi { public static function make():Int return 1; }");
		File.saveContent(haxe.io.Path.join([staticRoot, "Main.hx"]),
			"class Main { public static var value:Int = InitApi.make(); public static function main():Void {} }");
		final args = [
			"--hxhx-no-run",
			"--hxhx-no-emit",
			"--hxhx-server-report",
			"-cp",
			staticRoot,
			"-main",
			"Main"
		];
		final sourceCache = new CompilationServerSourceCache();
		final dependencyCatalog = new CompilationServerDependencyCatalog();
		final firstReply = compile(sourceCache, dependencyCatalog, args);
		final firstWire = wire(firstReply);
		assertTrue(!firstReply.isError, "static-initialization baseline should compile: " + firstWire);
		final firstSnapshot = reportValue(firstWire, "hxhx_server_report.dependency_snapshot");

		File.saveContent(apiPath, "class InitApi { public static function make():Int return 2; }");
		final changedReply = compile(sourceCache, dependencyCatalog, args);
		final changedWire = wire(changedReply);
		assertTrue(!changedReply.isError, "static-initialization provider edit should compile: " + changedWire);
		assertTrue(reportInt(changedWire, "hxhx_server_report.dependency_public_changes") == 0
			&& reportInt(changedWire, "hxhx_server_report.dependency_implementation_changes") == 1,
			"a provider body edit should preserve its public signature while changing its implementation");
		assertTrue(reportInt(changedWire, "hxhx_server_report.dependency_predicted_invalidations") == 2
			&& changedWire.indexOf(".module=Main") >= 0,
			"a provider body edit should reach the module whose static field consumes it");
		assertTrue(changedWire.indexOf("static-initialization:Main->InitApi:initializer:Main#static#value->type:InitApi@shared-typing") >= 0,
			"the public report should name the exact static field and provider type behind the selected body-sensitive edge");
		assertTrue(changedWire.indexOf(FileSystem.absolutePath(staticRoot)) < 0, "static-initialization reasons must not expose an absolute workspace path");

		File.saveContent(apiPath, "class InitApi { public static function make():Int return 1; }");
		final restoredReply = compile(sourceCache, dependencyCatalog, args);
		assertTrue(!restoredReply.isError, "restored static-initialization baseline should compile");
		assertTrue(reportValue(wire(restoredReply), "hxhx_server_report.dependency_snapshot") == firstSnapshot,
			"returning to exact static-initialization revision A should reproduce the original snapshot");
	}

	/**
		Prove both Stage3 typing exits publish the same normalized request settings.

		Each variant uses a fresh catalog, so the test compares sealed snapshot
		fingerprints rather than relying on the catalog's exact-argv history key.
	**/
	static function verifyProgramConfigurationSnapshots(root:String):Void {
		final configurationRoot = haxe.io.Path.join([root, "program-configuration"]);
		ensureDirectory(configurationRoot);
		File.saveContent(haxe.io.Path.join([configurationRoot, "Main.hx"]), "class Main { public static function main():Void {} }");
		final projectArgs = [
			"--hxhx-no-run",
			"--hxhx-server-report",
			"-cp",
			configurationRoot,
			"-main",
			"Main"
		];
		final configurationA = ["--dce", "full", "-D", "ocaml_profile=portable"];
		final noEmitA = wire(compile(new CompilationServerSourceCache(), new CompilationServerDependencyCatalog(),
			["--hxhx-no-emit"].concat(projectArgs).concat(configurationA)));
		final typeOnlyA = wire(compile(new CompilationServerSourceCache(), new CompilationServerDependencyCatalog(),
			["--hxhx-type-only"].concat(projectArgs).concat(configurationA)));
		final configurationAReordered = wire(compile(new CompilationServerSourceCache(), new CompilationServerDependencyCatalog(),
			["--hxhx-no-emit"].concat(projectArgs).concat(["-D", "ocaml_profile=portable", "--dce", "full"])));
		final baselineSnapshot = reportValue(noEmitA, "hxhx_server_report.dependency_snapshot");
		assertTrue(baselineSnapshot == reportValue(typeOnlyA, "hxhx_server_report.dependency_snapshot"),
			"type-only and no-emit requests should publish the same normalized program configuration");
		assertTrue(baselineSnapshot == reportValue(configurationAReordered, "hxhx_server_report.dependency_snapshot"),
			"define insertion order should not change the Stage3 dependency snapshot");

		final changedDce = wire(compile(new CompilationServerSourceCache(), new CompilationServerDependencyCatalog(),
			["--hxhx-no-emit"].concat(projectArgs).concat(["--dce", "no", "-D", "ocaml_profile=portable"])));
		assertTrue(baselineSnapshot != reportValue(changedDce, "hxhx_server_report.dependency_snapshot"),
			"changing DCE policy should change the sealed dependency snapshot even when source is unchanged");

		final changedProfile = wire(compile(new CompilationServerSourceCache(), new CompilationServerDependencyCatalog(),
			["--hxhx-no-emit"].concat(projectArgs).concat(["--dce", "full", "-D", "ocaml_profile=metal"])));
		assertTrue(baselineSnapshot != reportValue(changedProfile, "hxhx_server_report.dependency_snapshot"),
			"changing the normalized OCaml profile should change the sealed dependency snapshot");

		final changedTarget = wire(compile(new CompilationServerSourceCache(), new CompilationServerDependencyCatalog(),
			["--hxhx-backend", "js-native", "--hxhx-no-emit"].concat(projectArgs).concat(configurationA)));
		assertTrue(baselineSnapshot != reportValue(changedTarget, "hxhx_server_report.dependency_snapshot"),
			"changing the backend target should change the sealed dependency snapshot");

		final privateValue = "machine-private-value::configuration-secret";
		final privateConfiguration = wire(compile(new CompilationServerSourceCache(), new CompilationServerDependencyCatalog(),
			["--hxhx-no-emit"].concat(projectArgs).concat(["-D", "private_build=" + privateValue])));
		assertTrue(privateConfiguration.indexOf(privateValue) < 0,
			"the server report must not expose a raw define value retained by program-configuration observation");
	}

	/** A build macro must run before typing even when its module is discovered from a caller. **/
	static function verifyLazyGeneratedDeclarations(root:String):Void {
		final generatedRoot = haxe.io.Path.join([root, "lazy-generated-declarations"]);
		ensureDirectory(generatedRoot);
		File.saveContent(haxe.io.Path.join([generatedRoot, "Api.hx"]), [
			"@:build(hxhxmacros.BuildFieldMacros.addGeneratedField())",
			"class Api { public static function main():Void {} }"
		].join("\n"));
		File.saveContent(haxe.io.Path.join([generatedRoot, "Main.hx"]), [
			"import Api;",
			"class Main {",
			"  public static function main():Void {",
			"    var answer:Int = Api.generated_answer();",
			"    var repeated:Int = Api.generated_answer();",
			"  }",
			"}"
		].join("\n"));

		final commonArgs = [
			"--hxhx-no-run",
			"--hxhx-no-emit",
			"--hxhx-server-report",
			"--hxhx-macro-runtime",
			"inproc",
			"-D",
			"HXHX_BUILD_VARIANT=int",
			"-cp",
			generatedRoot
		];
		final reply = compile(new CompilationServerSourceCache(), new CompilationServerDependencyCatalog(), commonArgs.concat(["-main", "Main"]));
		final result = wire(reply);
		assertTrue(!reply.isError, "a caller should see a member generated on a lazily loaded module: " + result);
		final apiMacroLine = "build_macro[Api][0]=hxhxmacros.BuildFieldMacros.addGeneratedField()";
		assertTrue(countOccurrences(result, apiMacroLine) == 1, "repeated lookups should still run the lazy module's declared build macro exactly once");
		assertTrue(result.indexOf("build_fields[Api]=1") >= 0, "the lazy module should expose one generated member before typing");

		final rootReply = compile(new CompilationServerSourceCache(), new CompilationServerDependencyCatalog(), commonArgs.concat(["-main", "Api"]));
		final rootResult = wire(rootReply);
		assertTrue(!rootReply.isError, "the same annotated module should compile when selected directly: " + rootResult);
		assertTrue(countOccurrences(rootResult, apiMacroLine) == 1 && rootResult.indexOf("build_fields[Api]=1") >= 0,
			"root-first preparation should run the same macro once and expose the same generated member count");

		final packageRoot = haxe.io.Path.join([generatedRoot, "pack"]);
		ensureDirectory(packageRoot);
		File.saveContent(haxe.io.Path.join([packageRoot, "QualifiedApi.hx"]), [
			"package pack;",
			"@:build(hxhxmacros.BuildFieldMacros.addGeneratedField())",
			"class QualifiedApi {}"
		].join("\n"));
		File.saveContent(haxe.io.Path.join([generatedRoot, "QualifiedMain.hx"]), [
			"class QualifiedMain {",
			"  public static function main():Void {",
			"    var answer:Int = pack.QualifiedApi.generated_answer();",
			"  }",
			"}"
		].join("\n"));
		final qualifiedReply = compile(new CompilationServerSourceCache(), new CompilationServerDependencyCatalog(),
			commonArgs.concat(["-main", "QualifiedMain"]));
		final qualifiedResult = wire(qualifiedReply);
		assertTrue(!qualifiedReply.isError, "a fully qualified reference should prepare its lazily loaded module: " + qualifiedResult);
		assertTrue(countOccurrences(qualifiedResult, "build_macro[pack.QualifiedApi][0]=hxhxmacros.BuildFieldMacros.addGeneratedField()") == 1,
			"the fully qualified module should run its build macro exactly once");

		File.saveContent(haxe.io.Path.join([generatedRoot, "Base.hx"]),
			["@:build(hxhxmacros.BuildFieldMacros.addGeneratedField())", "class Base {}"].join("\n"));
		File.saveContent(haxe.io.Path.join([generatedRoot, "InheritanceMain.hx"]), [
			"class InheritanceMain extends Base {",
			"  public static function main():Void {}",
			"}"
		].join("\n"));
		final inheritanceReply = compile(new CompilationServerSourceCache(), new CompilationServerDependencyCatalog(),
			commonArgs.concat(["-main", "InheritanceMain"]));
		final inheritanceResult = wire(inheritanceReply);
		assertTrue(!inheritanceReply.isError, "a base class mentioned only by extends should be loaded and prepared: " + inheritanceResult);
		assertTrue(countOccurrences(inheritanceResult, "build_macro[Base][0]=hxhxmacros.BuildFieldMacros.addGeneratedField()") == 1,
			"the lazily discovered base class should run its declared build macro exactly once");
		assertTrue(inheritanceResult.indexOf("build_fields[Base]=1") >= 0,
			"the base class should expose its generated member before the derived class finishes typing");
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
			verifySourceOriginShadowing(root);
			verifySecondaryTypeReplacement(root);
			verifyConditionalCompilation(root);
			verifyGeneratedDeclarations(root);
			verifyStaticInitialization(root);
			verifyProgramConfigurationSnapshots(root);
			verifyLazyGeneratedDeclarations(root);
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
