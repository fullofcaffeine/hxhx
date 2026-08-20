import sys.FileSystem;
import sys.io.File;

/** Proves that qualified calls keep declared argument carriers and complete optional arguments. */
class M14Stage3WarningCleanShadowTraceIntegrationTest {
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

	static function emitOne(src:String, sourcePath:String, outDir:String):Void {
		final parsed = ParserStage.parse(src, sourcePath);
		final typed = TyperStage.typeModule(parsed);
		final expanded = MacroStage.expandProgram([typed], []);
		EmitterStage.emitToDir(expanded, outDir, true, false);
	}

	static function main():Void {
		final tmpRoot = haxe.io.Path.normalize('.tmp/m14_stage3_warning_clean_shadow_trace_' + Std.string(Date.now().getTime()));
		final traceOutDir = haxe.io.Path.join([tmpRoot, 'trace_out']);
		final shadowOutDir = haxe.io.Path.join([tmpRoot, 'shadow_out']);
		deleteRecursive(tmpRoot);
		FileSystem.createDirectory(tmpRoot);

		final tracePath = haxe.io.Path.join([tmpRoot, 'TraceUse.hx']);
		final traceSrc = [
			'class TraceUse {',
			'  public function new() {}',
			'  public function emit(s:String):Void {',
			'    haxe.Log.trace(s);',
			'  }',
			'}',
		].join("\n");
		File.saveContent(tracePath, traceSrc);

		final shadowPath = haxe.io.Path.join([tmpRoot, 'AsyncLike.hx']);
		final shadowSrc = [
			'class AsyncLike {',
			'  public function new() {}',
			'  public function branch(pos:Dynamic):Dynamic {',
			'    var branch:Dynamic = null;',
			'    branch.then(checkBranches.bind(pos));',
			'    return branch;',
			'  }',
			'  function checkBranches(pos:Dynamic):Void {}',
			'  function then(cb:Dynamic):Void {}',
			'}',
		].join("\n");
		File.saveContent(shadowPath, shadowSrc);

		var thrown:Dynamic = null;
		try {
			emitOne(traceSrc, tracePath, traceOutDir);
			final traceMl = haxe.io.Path.join([traceOutDir, 'TraceUse.ml']);
			assertTrue(FileSystem.exists(traceMl), 'Expected TraceUse.ml in emitted output.');
			final traceOcaml = File.getContent(traceMl);
			assertTrue(traceOcaml.indexOf('Haxe_Log.trace (Obj.repr (s)) ((Obj.magic HxRuntime.hx_null))') >= 0,
				'Expected haxe.Log.trace(value) to box its String argument and include a null PosInfos argument.');
			assertTrue(traceOcaml.indexOf('Haxe_Log.trace (s)') < 0, 'Expected the concrete String not to cross the declared Dynamic boundary without boxing.');
			assertTrue(traceOcaml.indexOf('Haxe_Log.trace (s));') < 0, 'Expected haxe.Log.trace(value) not to remain partially applied.');

			emitOne(shadowSrc, shadowPath, shadowOutDir);
			final shadowMl = haxe.io.Path.join([shadowOutDir, 'AsyncLike.ml']);
			assertTrue(FileSystem.exists(shadowMl), 'Expected AsyncLike.ml in emitted output.');
			final shadowOcaml = File.getContent(shadowMl);
			assertTrue(shadowOcaml.indexOf('then_ (branch)') >= 0, 'Expected local branch value to shadow the same-named instance method.');
			assertTrue(shadowOcaml.indexOf('branch (this_)') < 0, 'Expected local branch value not to lower as an instance method call.');
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
