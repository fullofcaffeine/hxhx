import backend.EmitArtifact;
import backend.EmitResult;
import hxhx.CompilationRequestContext;
import hxhx.CompilationServerReply;
import hxhx.CompilationServerProtocol;
import hxhx.CompilationServerRequest;
import hxhx.CompilationServerRequestCodec;
import hxhx.CompilationServerRequestDispatcher;
import hxhx.CompilationServerSourceCache;
import hxhx.Stage3Compiler;
import sys.FileSystem;
import sys.io.File;

/**
	Exercises the first native-server reuse layer through real Stage3 requests.

	The sequence checks both speed decisions and generated behavior. It deliberately
	changes files, defines, class-path winners, request outcomes, and the memory
	budget so a stale cache entry cannot pass merely because the same command was
	run twice.
**/
class M14CompilationServerSourceCacheIntegrationTest {
	static var nextRequestId:Int = 1000;

	static function assertTrue(condition:Bool, message:String):Void {
		if (!condition)
			throw message;
	}

	static function assertEquals(actual:String, expected:String, label:String):Void {
		assertTrue(actual == expected, label + " mismatch: expected `" + expected + "`, got `" + actual + "`");
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

	static function reportInt(wire:String, key:String):Int {
		final marker = key + "=";
		final markerIndex = wire.indexOf(marker);
		assertTrue(markerIndex >= 0, "server report should contain " + key);
		var end = markerIndex + marker.length;
		while (end < wire.length) {
			final code = wire.charCodeAt(end);
			if (code < 48 || code > 57)
				break;
			end += 1;
		}
		final parsed = Std.parseInt(wire.substring(markerIndex + marker.length, end));
		assertTrue(parsed != null, "server report should contain an integer for " + key);
		return parsed;
	}

	static function compile(cache:CompilationServerSourceCache, args:Array<String>, ?requestFlags:Array<String>):CompilationServerReply {
		nextRequestId += 1;
		return CompilationServerRequestDispatcher.dispatch(new CompilationServerRequest(nextRequestId, args, requestFlags == null ? [] : requestFlags, null),
			Stage3Compiler.runRequest, cache);
	}

	static function wire(reply:CompilationServerReply):String {
		return CompilationServerRequestCodec.encodeReply(reply);
	}

	/** Verify length-prefixing keeps otherwise ambiguous input lists distinct. **/
	static function verifyExactIdentityEncoding():Void {
		final splitValues = CompilerCacheIdentity.encode(["ab", "c"]);
		final joinedValue = CompilerCacheIdentity.encode(["a", "bc"]);
		final embeddedSeparator = CompilerCacheIdentity.encode(["a:1", "b\u0000c"]);
		final separateCharacters = CompilerCacheIdentity.encode(["a", ":1b\u0000c"]);
		assertTrue(splitValues != joinedValue, "cache identity should preserve value boundaries");
		assertTrue(embeddedSeparator != separateCharacters, "cache identity should treat separators as ordinary input characters");
		assertTrue(CompilerCacheIdentity.encode([null]) != CompilerCacheIdentity.encode([""]), "cache identity should distinguish null from empty text");
	}

	/** Verify exact filename case, secondary-type fallback, and direct-file precedence. **/
	static function verifyFilesystemResolution(root:String):Void {
		final srcDir = haxe.io.Path.join([root, "resolver"]);
		final packageDir = haxe.io.Path.join([srcDir, "pack"]);
		ensureDirectory(packageDir);
		final modulePath = haxe.io.Path.join([packageDir, "Mod.hx"]);
		File.saveContent(modulePath, "package pack; class Mod {} class SubType {}\n");

		final fallbackProvider = new CompilerSourceProvider();
		final missingClassPath = haxe.io.Path.join([root, "generated-source-not-created-yet"]);
		assertEquals(fallbackProvider.resolveModuleFile([missingClassPath, srcDir], "pack.Mod.SubType"), modulePath,
			"a class path that does not exist yet should behave like an empty directory");
		assertTrue(fallbackProvider.resolveModuleFile([srcDir], "pack.mod.SubType") == null, "module lookup should preserve exact filename case");
		fallbackProvider.finish(true);

		final createdDuringRequestRoot = haxe.io.Path.join([root, "created-during-request"]);
		final createdDuringRequestProvider = new CompilerSourceProvider();
		assertTrue(createdDuringRequestProvider.resolveModuleFile([createdDuringRequestRoot], "Generated") == null,
			"module should be absent before its class-path directory exists");
		ensureDirectory(createdDuringRequestRoot);
		final generatedPath = haxe.io.Path.join([createdDuringRequestRoot, "Generated.hx"]);
		File.saveContent(generatedPath, "class Generated {}\n");
		assertEquals(createdDuringRequestProvider.resolveModuleFile([createdDuringRequestRoot], "Generated"), generatedPath,
			"the same request should observe a source file created after an earlier miss");
		createdDuringRequestProvider.finish(true);

		final directDir = haxe.io.Path.join([packageDir, "Mod"]);
		ensureDirectory(directDir);
		final directPath = haxe.io.Path.join([directDir, "SubType.hx"]);
		File.saveContent(directPath, "package pack.Mod; class SubType {}\n");
		final directProvider = new CompilerSourceProvider();
		assertEquals(directProvider.resolveModuleFile([srcDir], "pack.Mod.SubType"), directPath,
			"direct module file should take precedence over secondary-type fallback");
		directProvider.finish(true);
	}

	/**
		Verify unchanged reuse, content changes, rollback to an older exact revision,
		failed-request isolation, reset, parser-input changes, and cancellation.
	**/
	static function verifyRequestLifecycle(root:String):Void {
		final srcDir = haxe.io.Path.join([root, "lifecycle"]);
		ensureDirectory(srcDir);
		final mainPath = haxe.io.Path.join([srcDir, "Main.hx"]);
		final sourceA = "class Main { static function main():Void {} }\n";
		File.saveContent(mainPath, sourceA);
		final args = [
			"--hxhx-no-run",
			"--hxhx-no-emit",
			"--hxhx-server-report",
			"-cp",
			srcDir,
			"-main",
			"Main"
		];
		final cache = new CompilationServerSourceCache();

		final cold = compile(cache, args);
		final coldWire = wire(cold);
		assertTrue(!cold.isError, "cold source-cache request should compile");
		assertTrue(coldWire.indexOf("hxhx_server_report.semantic_cache=source-resolution-parser") >= 0,
			"source-cache request should identify each enabled layer");
		assertTrue(reportInt(coldWire, "hxhx_server_report.source_misses") == 1, "cold request should read a new source revision");
		assertTrue(reportInt(coldWire, "hxhx_server_report.parser_misses") == 1, "cold request should parse once");
		assertTrue(reportInt(coldWire, "hxhx_server_report.resolution_misses") > 0, "cold request should record its module lookup observations");

		final warm = compile(cache, args);
		final warmWire = wire(warm);
		assertTrue(!warm.isError, "warm source-cache request should compile");
		assertTrue(reportInt(warmWire, "hxhx_server_report.source_hits") == 1, "warm request should reuse exact source text");
		assertTrue(reportInt(warmWire, "hxhx_server_report.parser_hits") == 1, "warm request should reuse its parsed module");
		assertTrue(reportInt(warmWire, "hxhx_server_report.resolution_hits") > 0, "warm request should reuse module lookup results");
		assertTrue(reportInt(warmWire, "hxhx_server_report.resolution_misses") == 0, "unchanged module lookup observations should not miss");
		assertTrue(reportInt(warmWire, "hxhx_server_report.semantic_cache_entries") >= 3, "warm request should retain source, parser, and lookup entries");

		// Equal bytes with new filesystem metadata are still the same compiler input.
		File.saveContent(mainPath, sourceA);
		final sameBytes = wire(compile(cache, args));
		assertTrue(reportInt(sameBytes, "hxhx_server_report.source_hits") == 1, "same-byte rewrite should reuse exact source content");
		assertTrue(reportInt(sameBytes, "hxhx_server_report.parser_hits") == 1, "same-byte rewrite should reuse the parsed module");

		final sourceB = "class Main { static function main():Void {} } // revision B\n";
		File.saveContent(mainPath, sourceB);
		final changed = compile(cache, args);
		final changedWire = wire(changed);
		assertTrue(!changed.isError, "changed source should compile");
		assertTrue(reportInt(changedWire, "hxhx_server_report.source_misses") == 1, "changed bytes should miss the source cache");
		assertTrue(reportInt(changedWire, "hxhx_server_report.parser_misses") == 1, "changed filtered source should be parsed again");
		assertTrue(changedWire.indexOf(".name=source-changed") >= 0, "changed source should explain why it missed");

		File.saveContent(mainPath, sourceA);
		final restored = wire(compile(cache, args));
		assertTrue(reportInt(restored, "hxhx_server_report.source_hits") == 1, "returning to revision A should reuse A source");
		assertTrue(reportInt(restored, "hxhx_server_report.parser_hits") == 1, "returning to revision A should reuse A parser output");

		final invalidSource = "class Main { static function main():Void { trace(\"unterminated); } }\n";
		File.saveContent(mainPath, invalidSource);
		assertTrue(compile(cache, args).isError, "malformed source should fail without publishing cache candidates");
		final repeatedFailure = compile(cache, args);
		assertTrue(repeatedFailure.isError, "repeated malformed source should still fail");
		assertTrue(reportInt(wire(repeatedFailure), "hxhx_server_report.source_misses") == 1, "failed request must not publish its source candidate");

		File.saveContent(mainPath, sourceA);
		final afterFailure = compile(cache, args);
		assertTrue(!afterFailure.isError, "last known good source should compile after failed requests");
		assertTrue(reportInt(wire(afterFailure), "hxhx_server_report.parser_hits") == 1, "failed parser work must not replace the last known good entry");

		final reset = compile(cache, [], ["--hxhx-server-control", "reset"]);
		assertTrue(!reset.isError && wire(reset).indexOf("hxhx_server_control.reset=ok") >= 0, "cache reset should confirm completion");
		final afterReset = wire(compile(cache, args));
		assertTrue(reportInt(afterReset, "hxhx_server_report.source_misses") == 1, "reset should make source content cold again");
		assertTrue(reportInt(afterReset, "hxhx_server_report.parser_misses") == 1, "reset should make parser output cold again");

		// Parsed declarations expose mutable arrays. Reject a changed tree before it
		// can become a later request's supposedly immutable cache entry.
		final integrityCache = new CompilationServerSourceCache();
		final mutableProvider = integrityCache.openRequest();
		final integrityPath = mutableProvider.resolveModuleFile([srcDir], "Main");
		final integritySource = mutableProvider.readSource(integrityPath);
		final mutatedParsed = mutableProvider.parseFilteredSource(integritySource, integrityPath);
		HxModuleDecl.getImports(mutatedParsed.getDecl()).push("Injected.Mutation");
		var mutationRejected = false;
		try {
			mutableProvider.finish(true);
		} catch (error:String) {
			mutationRejected = error.indexOf("parsed module changed after the cache recorded it") >= 0;
		}
		assertTrue(mutationRejected, "mutated parser result should fail before cache publication");

		// A later request can accidentally mutate an entry that was already reused.
		// Quarantine it during that request's validation so one bad request does not
		// force the following request to fail before it can reparse clean source.
		final seedProvider = integrityCache.openRequest();
		final seedPath = seedProvider.resolveModuleFile([srcDir], "Main");
		final seedSource = seedProvider.readSource(seedPath);
		seedProvider.parseFilteredSource(seedSource, seedPath);
		seedProvider.finish(true);
		final cachedMutationProvider = integrityCache.openRequest();
		final cachedMutationPath = cachedMutationProvider.resolveModuleFile([srcDir], "Main");
		final cachedMutationSource = cachedMutationProvider.readSource(cachedMutationPath);
		final cachedMutation = cachedMutationProvider.parseFilteredSource(cachedMutationSource, cachedMutationPath);
		assertTrue(cachedMutationProvider.report().parserHits == 1, "fixture should mutate a previously cached parser tree");
		HxModuleDecl.getImports(cachedMutation.getDecl()).push("Injected.CachedMutation");
		var cachedMutationRejected = false;
		try {
			cachedMutationProvider.finish(true);
		} catch (error:String) {
			cachedMutationRejected = error.indexOf("parsed module changed after the cache recorded it") >= 0;
		}
		assertTrue(cachedMutationRejected, "mutated cached parser result should fail its current request");
		final afterCachedMutationProvider = integrityCache.openRequest();
		final afterCachedMutationPath = afterCachedMutationProvider.resolveModuleFile([srcDir], "Main");
		final afterCachedMutationSource = afterCachedMutationProvider.readSource(afterCachedMutationPath);
		afterCachedMutationProvider.parseFilteredSource(afterCachedMutationSource, afterCachedMutationPath);
		assertTrue(afterCachedMutationProvider.report().parserMisses == 1,
			"request after cached-tree mutation should reparse instead of reusing the quarantined tree");
		afterCachedMutationProvider.finish(true);

		final conditional = "class Main { static function main():Void {\n#if CACHE_FLAG\ntrace(\"flag\");\n#else\ntrace(\"plain\");\n#end\n} }\n";
		File.saveContent(mainPath, conditional);
		final defineCache = new CompilationServerSourceCache();
		assertTrue(!compile(defineCache, args).isError, "conditional source should compile without the define");
		final changedDefine = compile(defineCache, args.concat(["-D", "CACHE_FLAG"]));
		final changedDefineWire = wire(changedDefine);
		assertTrue(!changedDefine.isError, "conditional source should compile with the define");
		assertTrue(reportInt(changedDefineWire, "hxhx_server_report.source_hits") == 1, "define change should reuse equal on-disk source bytes");
		assertTrue(reportInt(changedDefineWire, "hxhx_server_report.parser_misses") == 1, "define change that changes filtered source should parse again");

		File.saveContent(mainPath, sourceA);
		final cancelledCache = new CompilationServerSourceCache();
		assertTrue(compile(cancelledCache, args, [CompilationServerProtocol.REQUEST_TIMEOUT_FLAG, "0"]).isError, "cancelled cache request should fail");
		final afterCancellation = wire(compile(cancelledCache, args));
		assertTrue(reportInt(afterCancellation, "hxhx_server_report.source_misses") == 1, "cancelled request must not publish a source entry");
	}

	/** Verify that generated-output publication must succeed before cache publication. **/
	static function verifyOutputFailureIsolation(root:String):Void {
		final srcDir = haxe.io.Path.join([root, "output-failure"]);
		ensureDirectory(srcDir);
		File.saveContent(haxe.io.Path.join([srcDir, "Main.hx"]), "class Main { static function main():Void {} }\n");
		final cache = new CompilationServerSourceCache();
		final provider = cache.openRequest();
		nextRequestId += 1;
		final context = CompilationRequestContext.server(nextRequestId, provider);
		final modulePath = provider.resolveModuleFile([srcDir], "Main");
		final source = provider.readSource(modulePath);
		provider.parseFilteredSource(source, modulePath);

		final finalOutput = haxe.io.Path.join([root, "output-failure-result"]);
		final paths = context.prepareOutput(finalOutput, finalOutput, null);
		ensureDirectory(haxe.io.Path.directory(paths.workingOutDir));
		File.saveContent(paths.workingOutDir, "this file deliberately prevents directory publication");
		final stagedEntry = haxe.io.Path.join([paths.workingOutDir, "main.js"]);
		context.sealOutput(new EmitResult(stagedEntry, [new EmitArtifact("entry_js", stagedEntry)], false));
		assertTrue(!context.close(true), "output-publication failure should fail the request");

		final probe = cache.openRequest();
		final probePath = probe.resolveModuleFile([srcDir], "Main");
		final probeSource = probe.readSource(probePath);
		probe.parseFilteredSource(probeSource, probePath);
		assertTrue(probe.report().resolutionMisses > 0, "failed output request must not publish module lookup candidates");
		assertTrue(probe.report().sourceMisses == 1, "failed output request must not publish source candidates");
		assertTrue(probe.report().parserMisses == 1, "failed output request must not publish parser candidates");
		probe.finish(false);
	}

	/** Verify add, rename, and class-path shadowing against generated target bytes. **/
	static function verifyClassPathShadowing(root:String):Void {
		final shadowRoot = haxe.io.Path.join([root, "shadow"]);
		final high = haxe.io.Path.join([shadowRoot, "high"]);
		final low = haxe.io.Path.join([shadowRoot, "low"]);
		ensureDirectory(high);
		ensureDirectory(low);
		final highMain = haxe.io.Path.join([high, "Main.hx"]);
		final lowMain = haxe.io.Path.join([low, "Main.hx"]);
		File.saveContent(lowMain, "class Main { static function main():Void { trace(\"lower\"); } }\n");
		final artifact = haxe.io.Path.join([shadowRoot, "out", "main.js"]);
		final args = [
			"--hxhx-no-run", "--hxhx-server-report", "--hxhx-backend", "js-native",  "--js", artifact,
			          "-cp",                   high,            "-cp",         low, "-main",   "Main"
		];
		final cache = new CompilationServerSourceCache();
		assertTrue(!compile(cache, args).isError, "lower-priority module should compile while the earlier class path is empty");
		final lowerOutput = File.getContent(artifact);
		assertTrue(lowerOutput.indexOf("lower") >= 0, "first build should emit the lower-priority source");

		File.saveContent(highMain, "class Main { static function main():Void { trace(\"higher\"); } }\n");
		final higher = compile(cache, args);
		final higherOutput = File.getContent(artifact);
		assertTrue(!higher.isError && higherOutput.indexOf("higher") >= 0 && higherOutput != lowerOutput,
			"new higher-priority module should replace the older generated output");
		assertTrue(wire(higher).indexOf(".name=origin-shadowed") >= 0, "module lookup should explain that a different origin won");

		FileSystem.rename(highMain, haxe.io.Path.join([high, "MovedMain.hx"]));
		final restored = compile(cache, args);
		assertTrue(!restored.isError, "renaming the shadowing file away should restore the lower-priority module");
		assertEquals(File.getContent(artifact), lowerOutput, "generated output after restoring lower-priority module");
		assertTrue(reportInt(wire(restored), "hxhx_server_report.resolution_hits") > 0, "returning to old lookup observations should reuse their exact result");
	}

	/** Verify that exceeding the configured estimate only removes reuse, never correctness. **/
	static function verifyEviction(root:String):Void {
		final srcDir = haxe.io.Path.join([root, "eviction"]);
		ensureDirectory(srcDir);
		File.saveContent(haxe.io.Path.join([srcDir, "Main.hx"]),
			"class Main { static function main():Void {} }\n/*" + StringTools.lpad("", "x", 4096) + "*/\n");
		final args = [
			"--hxhx-no-run",
			"--hxhx-no-emit",
			"--hxhx-server-report",
			"-cp",
			srcDir,
			"-main",
			"Main"
		];
		final cache = new CompilationServerSourceCache(1024);
		final first = compile(cache, args);
		assertTrue(!first.isError, "request should compile even when its entries exceed the cache budget");
		assertTrue(reportInt(wire(first), "hxhx_server_report.cache_evictions") > 0, "tiny cache budget should evict entries after request release");
		assertTrue(!compile(cache, args).isError, "evicted compiler facts should be recomputed correctly");
	}

	static function main():Void {
		final root = ".tmp/m14_compilation_server_source_cache";
		deleteRecursive(root);
		ensureDirectory(root);
		var failure:Dynamic = null;
		try {
			verifyExactIdentityEncoding();
			verifyFilesystemResolution(root);
			verifyRequestLifecycle(root);
			verifyOutputFailureIsolation(root);
			verifyClassPathShadowing(root);
			verifyEviction(root);
		} catch (error:Dynamic) {
			failure = error;
		}
		deleteRecursive(root);
		if (failure != null)
			throw failure;
	}
}
