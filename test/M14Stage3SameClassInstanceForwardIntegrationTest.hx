import sys.FileSystem;
import sys.io.File;

/** Exact instance calls retain their receiver and arguments and order local declarations correctly. */
class M14Stage3SameClassInstanceForwardIntegrationTest {
	static function assertTrue(cond:Bool, message:String):Void {
		if (!cond)
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

	static function main():Void {
		final tmpRoot = haxe.io.Path.normalize('.tmp/m14_stage3_same_class_instance_forward_' + Std.string(Date.now().getTime()));
		final outDir = haxe.io.Path.join([tmpRoot, 'out']);
		deleteRecursive(tmpRoot);
		FileSystem.createDirectory(tmpRoot);

		final sourcePath = haxe.io.Path.join([tmpRoot, 'Runner.hx']);
		final src = [
			'class Runner {',
			'  var source:String;',
			'  public static inline function callConstructed(source:String):Dynamic return new Runner(source).readConstructed();',
			'  public function new(?source:String) { this.source = source; }',
			'  function readConstructed():Dynamic return source;',
			'  public function addCase(test:Dynamic, setup = "setup", teardown = "teardown", prefix = "test", ?pattern:Dynamic, setupAsync = "setupAsync", teardownAsync = "teardownAsync") {',
			'    addCaseOld(test, setup, teardown, prefix, pattern, setupAsync, teardownAsync);',
			'  }',
			'  function addCaseOld(test:Dynamic, setup = "setup", teardown = "teardown", prefix = "test", ?pattern:Dynamic, setupAsync = "setupAsync", teardownAsync = "teardownAsync") {}',
			'  function touch() {',
			'    mark();',
			'  }',
			'  function mark() {}',
			'  static function main():Void { Sys.println(Std.string(callConstructed("value"))); }',
			'}',
		].join("\n");
		File.saveContent(sourcePath, src);
		final exactConstructedCall = TypedExactCallSource.encodeInstance("Runner", "Runner.readConstructed", "readConstructed", "Dynamic",
			HxExpr.ENew("Runner", [HxExpr.EString("value")]), []);
		assertTrue(backend.ocaml.OcamlLocalCallDependency.calleeName(exactConstructedCall) == "readConstructed",
			'Expected exact instance-call metadata to expose the local callee used for OCaml ordering.');

		var thrown:Dynamic = null;
		try {
			M14Stage3RuntimeFixture.observe({command: "haxe", arguments: ["-cp", tmpRoot, "--run", "Runner"], expected: "value\n"});
			final parsed = ParserStage.parse(src, sourcePath);
			// Defaulted instance methods need the declaration that owns their receiver.
			final resolved = new ResolvedModule("Runner", sourcePath, parsed);
			final typed = TyperStage.typeResolvedModule(resolved, TyperIndex.build([resolved]));
			final expanded = MacroStage.expandProgram([typed], []);
			final executable = EmitterStage.emitToDir(expanded, outDir);
			M14Stage3RuntimeFixture.observe({command: executable, arguments: [], expected: "value\n"});

			final runnerMl = haxe.io.Path.join([outDir, 'Runner.ml']);
			assertTrue(FileSystem.exists(runnerMl), 'Expected Runner.ml in emitted output.');
			final ocaml = File.getContent(runnerMl);
			assertTrue(ocaml.indexOf('addCaseOld (this_) (test) (setup) (teardown) (prefix) (Obj.repr (pattern)) (setupAsync) (teardownAsync)') >= 0,
				'Expected same-class forwarding to retain one receiver, argument order, and the optional Dynamic representation.');
			assertTrue(ocaml.indexOf('addCaseOld (test) (setup)') < 0, 'Expected forwarded instance call not to omit the receiver.');
			assertTrue(ocaml.indexOf('mark (this_)') >= 0, 'Expected zero-argument same-class instance method call to include this_.');
			assertTrue(ocaml.indexOf('mark (this_) ()') < 0, 'Expected zero-argument same-class instance method call not to append unit.');
			final constructedCalleeIndex = ocaml.indexOf('let rec readConstructed');
			final constructedCallerIndex = ocaml.indexOf('let rec callConstructed');
			assertTrue(constructedCalleeIndex >= 0 && constructedCallerIndex >= 0 && constructedCalleeIndex < constructedCallerIndex,
				'Expected a method called on a constructed receiver to be emitted before its caller.');
			Sys.println("SAME_CLASS_INSTANCE_FORWARD:PASS");
		} catch (e:Dynamic) {
			thrown = e;
		}

		if (thrown != null) {
			Sys.println('debug_out=' + tmpRoot);
			throw thrown;
		}
		deleteRecursive(tmpRoot);
	}
}
