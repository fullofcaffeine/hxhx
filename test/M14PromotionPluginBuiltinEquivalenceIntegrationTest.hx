import backend.BackendContext;
import backend.BackendRegistry;
import backend.IBackend;
import backend.js.JsBackend;
import haxe.io.Path;
import sys.FileSystem;
import sys.io.File;

class M14PromotionPluginBuiltinEquivalenceIntegrationTest {
	static function assertTrue(condition:Bool, message:String):Void {
		if (!condition)
			throw message;
	}

	static function assertContains(haystack:String, needle:String, label:String):Void {
		if (haystack.indexOf(needle) < 0)
			throw label + " (missing `" + needle + "`)";
	}

	static function deleteRecursive(path:String):Void {
		if (!FileSystem.exists(path))
			return;
		if (FileSystem.isDirectory(path)) {
			for (entry in FileSystem.readDirectory(path)) {
				deleteRecursive(Path.join([path, entry]));
			}
			FileSystem.deleteDirectory(path);
			return;
		}
		FileSystem.deleteFile(path);
	}

	static function makeProgram(source:String, filePath:String):MacroExpandedProgram {
		final parsed = ParserStage.parse(source, filePath);
		final typed = TyperStage.typeModule(parsed);
		return MacroStage.expandProgram([typed], []);
	}

	static function runNodeScript(jsPath:String):String {
		final process = new sys.io.Process("node", [jsPath]);
		final stdout = process.stdout.readAll().toString();
		final stderr = process.stderr.readAll().toString();
		final exitCode = process.exitCode();
		process.close();
		assertTrue(exitCode == 0, "node execution failed for " + jsPath + " with exit " + exitCode + ": " + stderr);
		return StringTools.trim(stdout);
	}

	static function emitWithBackend(backend:IBackend, program:MacroExpandedProgram, outDir:String):String {
		FileSystem.createDirectory(outDir);
		final artifactPath = Path.join([outDir, "main.js"]);
		final context = new BackendContext(outDir, artifactPath, "Main", true, false, HxDefineMap.fromRawDefines(["js=1", "js-es=5"]));
		final result = backend.emit(program, context);
		assertTrue(result.entryPath == artifactPath, "unexpected artifact path for backend " + backend.id());
		assertTrue(FileSystem.exists(artifactPath), "missing emitted artifact for backend " + backend.id());
		return artifactPath;
	}

	static function main():Void {
		final tmpRoot = Path.normalize(".tmp/m14_plugin_builtin_equivalence_" + Std.string(Date.now().getTime()));
		final builtinOut = Path.join([tmpRoot, "builtin_out"]);
		final pluginOut = Path.join([tmpRoot, "plugin_out"]);
		deleteRecursive(tmpRoot);
		FileSystem.createDirectory(tmpRoot);

		var failure:Null<String> = null;
		try {
			BackendRegistry.clearDynamicRegistrations();
			final beforeDescriptor = BackendRegistry.descriptorForTarget("js-native");
			assertTrue(beforeDescriptor != null && beforeDescriptor.implId == JsBackend.IMPL_ID,
				"expected builtin js-native descriptor before plugin registration");

			final registered = BackendRegistry.registerProvider(JsBackend.providerRegistrations());
			assertTrue(registered == 1, "expected one provider registration for js-native promotion pilot");
			final afterDescriptor = BackendRegistry.descriptorForTarget("js-native");
			assertTrue(afterDescriptor != null && afterDescriptor.implId == JsBackend.PROVIDER_IMPL_ID,
				"provider registration should deterministically win js-native resolution");

			final source = [
				"class Main {",
				"  static function main() {",
				"    var xs = [1, 2, 3];",
				"    var total = 0;",
				"    for (i in 0...xs.length) {",
				"      total += xs[i];",
				"    }",
				"    Sys.println(\"sum=\" + total);",
				"  }",
				"}"
			].join("\n");
			final program = makeProgram(source, "PromotionEquivalenceMain.hx");

			final builtinBackend = new JsBackend();
			final pluginBackend = JsBackend.providerRegistrations()[0].create();
			assertTrue(pluginBackend.id() == JsBackend.TARGET_ID, "provider-backed backend should expose js-native target id");

			final builtinJs = emitWithBackend(builtinBackend, program, builtinOut);
			final pluginJs = emitWithBackend(pluginBackend, program, pluginOut);

			final builtinContent = File.getContent(builtinJs);
			final pluginContent = File.getContent(pluginJs);
			assertTrue(builtinContent == pluginContent, "builtin and provider wrappers should emit byte-identical JS artifacts");

			final builtinOutput = runNodeScript(builtinJs);
			final pluginOutput = runNodeScript(pluginJs);
			assertContains(builtinOutput, "sum=6", "builtin wrapper runtime output mismatch");
			assertContains(pluginOutput, "sum=6", "provider wrapper runtime output mismatch");
			assertTrue(builtinOutput == pluginOutput, "builtin and provider wrappers should preserve runtime equivalence");

			BackendRegistry.clearDynamicRegistrations();
			final afterClearDescriptor = BackendRegistry.descriptorForTarget("js-native");
			assertTrue(afterClearDescriptor != null && afterClearDescriptor.implId == JsBackend.IMPL_ID,
				"clearing dynamic registrations should restore builtin js-native precedence");
		} catch (message:String) {
			failure = message;
		} catch (error:haxe.Exception) {
			failure = error.message;
		}

		BackendRegistry.clearDynamicRegistrations();

		if (failure != null) {
			Sys.println("debug_out=" + tmpRoot);
			throw failure;
		}
		deleteRecursive(tmpRoot);
	}
}
