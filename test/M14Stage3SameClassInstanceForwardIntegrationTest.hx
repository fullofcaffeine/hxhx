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
		deleteRecursive(tmpRoot);
		FileSystem.createDirectory(tmpRoot);

		final sourcePath = haxe.io.Path.join([tmpRoot, 'Runner.hx']);
		final src = [
			'class Runner {',
			'  public function new() {}',
			'  public function addCase(test:Dynamic, setup = "setup", teardown = "teardown", prefix = "test", ?pattern:Dynamic, setupAsync = "setupAsync", teardownAsync = "teardownAsync") {',
			'    addCaseOld(test, setup, teardown, prefix, pattern, setupAsync, teardownAsync);',
			'  }',
			'  function addCaseOld(test:Dynamic, setup = "setup", teardown = "teardown", prefix = "test", ?pattern:Dynamic, setupAsync = "setupAsync", teardownAsync = "teardownAsync") {}',
			'}',
		].join("\n");
		File.saveContent(sourcePath, src);

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
