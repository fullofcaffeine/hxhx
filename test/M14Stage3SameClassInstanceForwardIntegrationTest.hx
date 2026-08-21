import sys.FileSystem;
import sys.io.File;

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
		final stubOutDir = haxe.io.Path.join([tmpRoot, 'stub-out']);
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
			'}',
		].join("\n");
		File.saveContent(sourcePath, src);
		final exactConstructedCall = TypedExactCallSource.encodeInstance("Runner", "Runner.readConstructed", "readConstructed", "Dynamic",
			HxExpr.ENew("Runner", [HxExpr.EString("value")]), []);
		assertTrue(backend.ocaml.OcamlLocalCallDependency.calleeName(exactConstructedCall) == "readConstructed",
			'Expected exact instance-call metadata to expose the local callee used for OCaml ordering.');

		var thrown:Dynamic = null;
		try {
			final parsed = ParserStage.parse(src, sourcePath);
			final typed = TyperStage.typeModule(parsed);
			final expanded = MacroStage.expandProgram([typed], []);
			EmitterStage.emitToDir(expanded, outDir, true, false);

			final runnerMl = haxe.io.Path.join([outDir, 'Runner.ml']);
			assertTrue(FileSystem.exists(runnerMl), 'Expected Runner.ml in emitted output.');
			final ocaml = File.getContent(runnerMl);
			assertTrue(ocaml.indexOf('addCaseOld (this_) (test) (setup) (teardown) (prefix) (pattern) (setupAsync) (teardownAsync)') >= 0,
				'Expected same-class instance method forwarding to include this_ before forwarded arguments.');
			assertTrue(ocaml.indexOf('addCaseOld (test) (setup)') < 0, 'Expected forwarded instance call not to omit the receiver.');
			assertTrue(ocaml.indexOf('mark (this_)') >= 0, 'Expected zero-argument same-class instance method call to include this_.');
			assertTrue(ocaml.indexOf('mark (this_) ()') < 0, 'Expected zero-argument same-class instance method call not to append unit.');
			final constructedCalleeIndex = ocaml.indexOf('let rec readConstructed');
			final constructedCallerIndex = ocaml.indexOf('let rec callConstructed');
			assertTrue(constructedCalleeIndex >= 0 && constructedCallerIndex >= 0 && constructedCalleeIndex < constructedCallerIndex,
				'Expected a method called on a constructed receiver to be emitted before its caller.');
			assertTrue(ocaml.indexOf('readConstructed ((let __hx_obj = HxAnon.create ()') >= 0,
				'Expected a constructed receiver to remain the first argument of its exact instance call.');

			EmitterStage.emitToDir(expanded, stubOutDir, false, false);
			final stubOcaml = File.getContent(haxe.io.Path.join([stubOutDir, 'Runner.ml']));
			final stubConstructedCalleeIndex = stubOcaml.indexOf('let rec readConstructed');
			final stubConstructedCallerIndex = stubOcaml.indexOf('let rec callConstructed');
			assertTrue(stubConstructedCalleeIndex >= 0
				&& stubConstructedCallerIndex >= 0
				&& stubConstructedCalleeIndex < stubConstructedCallerIndex,
				'Expected exact instance-call metadata to keep a later method declaration before its stub-body caller.');
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
