import backend.BackendContext;
import backend.BackendDispatchBoundary;
import backend.BackendRegistry;
import backend.vm.NekoTargetCore;
import haxe.io.Path;
import sys.FileSystem;
import sys.io.File;

class M14NekoNativeBackendSmokeIntegrationTest {
	static function assertTrue(cond:Bool, message:String):Void {
		if (!cond)
			throw message;
	}

	static function assertContains(haystack:String, needle:String, message:String):Void {
		if (haystack.indexOf(needle) < 0)
			throw message + " (missing `" + needle + "` in `" + haystack + "`)";
	}

	static function assertNotContains(haystack:String, needle:String, message:String):Void {
		if (haystack.indexOf(needle) >= 0)
			throw message + " (unexpected `" + needle + "` in `" + haystack + "`)";
	}

	static function assertFailsContains(fn:Void->Void, expected:String):Void {
		var message = "";
		try {
			fn();
		} catch (e:haxe.Exception) {
			message = e.message;
		} catch (e:String) {
			message = e;
		}
		assertTrue(message.indexOf(expected) >= 0, "expected failure containing `" + expected + "`, got `" + message + "`");
	}

	static function deleteRecursive(path:String):Void {
		if (!FileSystem.exists(path))
			return;
		if (FileSystem.isDirectory(path)) {
			for (entry in FileSystem.readDirectory(path))
				deleteRecursive(Path.join([path, entry]));
			FileSystem.deleteDirectory(path);
		} else {
			FileSystem.deleteFile(path);
		}
	}

	static function program(source:String) {
		final parsed = ParserStage.parse(source, "Main.hx");
		final typed = TyperStage.typeModule(parsed);
		return MacroStage.expandProgram([typed], []);
	}

	static function main():Void {
		final outDir = Path.join([".tmp", "m14_neko_native_backend_smoke"]);
		deleteRecursive(outDir);
		FileSystem.createDirectory(outDir);

		final defines = new haxe.ds.StringMap<String>();
		defines.set(NekoTargetCore.SOURCE_ONLY_DEFINE, "1");
		final outputHint = Path.join([outDir, "main.n"]);
		final context = new BackendContext(outDir, outputHint, "Main", true, false, defines);
		final backend = BackendRegistry.createForTarget("neko-native");
		final result = BackendDispatchBoundary.emit(backend, program('class Main { static function main() { Sys.println("hello neko"); } }'), context);

		final sourcePath = Path.join([outDir, "main.neko"]);
		assertTrue(result.entryPath == sourcePath, "source-only mode should report the generated Neko source as entry path");
		assertTrue(FileSystem.exists(sourcePath), "expected generated Neko source file");
		final source = File.getContent(sourcePath);
		assertContains(source, "var Main_main = function()", "expected generated static main function");
		assertContains(source, "$print(\"hello neko\", \"\\n\")", "expected Sys.println lowering");
		assertContains(source, "Main_main();", "expected entrypoint invocation");

		deleteRecursive(outDir);

		FileSystem.createDirectory(outDir);
		final anonResult = BackendDispatchBoundary.emit(backend,
			program('class Main { static function main() { var o = { name: "neko", count: 2 }; Sys.println(o.name); } }'), context);
		assertTrue(anonResult.entryPath == sourcePath, "anon source-only mode should report generated Neko source");
		final anonSource = File.getContent(sourcePath);
		assertContains(anonSource, "var __hxhx_o = $new(null);", "expected Neko object allocation for anonymous object literal");
		assertContains(anonSource, "__hxhx_o.name = \"neko\";", "expected anonymous object string field assignment");
		assertContains(anonSource, "__hxhx_o.count = 2;", "expected anonymous object int field assignment");

		deleteRecursive(outDir);

		FileSystem.createDirectory(outDir);
		BackendDispatchBoundary.emit(backend, program('class Main { static function main() { var o = new TestOps(7); } }'), context);
		final newSource = File.getContent(sourcePath);
		assertContains(newSource, "__hxhx_o.__hx_ctor = \"TestOps\";", "expected constructor tag on lowered Neko object");
		assertContains(newSource, "__hxhx_o.__hx_params = $array(7);", "expected constructor args on lowered Neko object");

		deleteRecursive(outDir);

		FileSystem.createDirectory(outDir);
		BackendDispatchBoundary.emit(backend, program('class Main { static function main() { var f = x -> x; Sys.println(f(3)); } }'), context);
		final lambdaSource = File.getContent(sourcePath);
		assertContains(lambdaSource, "var f = function(x) { return x; };", "expected Neko lambda lowering");
		assertContains(lambdaSource, "$print(f(3), \"\\n\")", "expected lambda call lowering");
		deleteRecursive(outDir);

		FileSystem.createDirectory(outDir);
		BackendDispatchBoundary.emit(backend,
			program('class Main { static function main() { var label = switch (1) { case 1: "one"; default: "other"; }; Sys.println(label); } }'), context);
		final switchSource = File.getContent(sourcePath);
		assertContains(switchSource, 'var label = switch 1 { 1 => "one" default => "other" };', "expected Neko switch expression lowering");
		deleteRecursive(outDir);

		FileSystem.createDirectory(outDir);
		BackendDispatchBoundary.emit(backend, program('class Main { static function main() { for (i in [1, 2]) Sys.println(i); } }'), context);
		final forSource = File.getContent(sourcePath);
		assertContains(forSource, "var __hxhx_iter_i = $array(1, 2);", "expected Neko for-in iterable temp");
		assertContains(forSource, "while (__hxhx_index_i < $asize(__hxhx_iter_i))", "expected Neko for-in while lowering");
		assertContains(forSource, "var i = __hxhx_iter_i[__hxhx_index_i];", "expected Neko for-in value binding");

		deleteRecursive(outDir);

		FileSystem.createDirectory(outDir);
		BackendDispatchBoundary.emit(backend,
			program('class Main { static function main() { var verbose = Sys.args().indexOf("-v") >= 0; var values = [1]; values.push(2); Sys.println(verbose); } }'),
			context);
		final arrayMethodSource = File.getContent(sourcePath);
		assertContains(arrayMethodSource, "var __hxhx_array_indexOf = function(a, value)", "expected Neko array indexOf helper");
		assertContains(arrayMethodSource, "var __hxhx_array_push = function(a, value)", "expected Neko array push helper");
		assertContains(arrayMethodSource, 'var verbose = (__hxhx_array_indexOf($$loader.args, "-v") >= 0);', "expected Sys.args().indexOf lowering");
		assertContains(arrayMethodSource, "__hxhx_array_push(values, 2);", "expected array push lowering");

		deleteRecursive(outDir);

		FileSystem.createDirectory(outDir);
		BackendDispatchBoundary.emit(backend,
			program('class Main { static function main() { if (neko.Web.isModNeko) neko.Web.setHeader("Content-Type", "text/plain"); Sys.println("ok"); } }'),
			context);
		final webSource = File.getContent(sourcePath);
		assertContains(webSource, "if false", "expected neko.Web.isModNeko CLI lowering");
		assertContains(webSource, "null;", "expected neko.Web.setHeader no-op lowering");

		deleteRecursive(outDir);

		FileSystem.createDirectory(outDir);
		BackendDispatchBoundary.emit(backend,
			program('package unit; class UnitBuilder { public static function generateSpec(path:String) return [path]; } class Main { static function main() { var specs = unit.UnitBuilder.generateSpec("src/unitstd"); Sys.println(specs.length); } }'),
			context);
		final unitBuilderSource = File.getContent(sourcePath);
		assertContains(unitBuilderSource, "var specs = $array();", "expected compile-time-only UnitBuilder.generateSpec fallback");

		deleteRecursive(outDir);

		FileSystem.createDirectory(outDir);
		BackendDispatchBoundary.emit(backend,
			program('class Main { static function main() { TestIssues.addIssueClasses("src/unit/issues", "unit.issues"); Sys.println("ok"); } }'), context);
		final testIssuesSource = File.getContent(sourcePath);
		assertContains(testIssuesSource, "null;", "expected compile-time-only TestIssues.addIssueClasses fallback");

		deleteRecursive(outDir);

		FileSystem.createDirectory(outDir);
		BackendDispatchBoundary.emit(backend,
			program('class Main { static function main() { var runner = new Runner(); runner.addCase(1); Report.create(runner); } }'), context);
		final receiverCallSource = File.getContent(sourcePath);
		assertContains(receiverCallSource, "runner.addCase(1);", "expected lowercase receiver method call to stay qualified");
		assertContains(receiverCallSource, "Report_create(runner);", "expected uppercase static call to keep static lowering");
		assertNotContains(receiverCallSource, "runner_addCase(1);", "lowercase receiver call must not become static free function");

		deleteRecursive(outDir);

		FileSystem.createDirectory(outDir);
		assertFailsContains(function() {
			BackendDispatchBoundary.emit(backend, program('class Main { static function main() { for (i in 0...2) Sys.println(i); } }'), context);
		}, "ERange");
		deleteRecursive(outDir);
	}
}
