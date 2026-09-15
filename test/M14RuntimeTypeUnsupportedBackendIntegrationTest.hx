import backend.BackendContext;
import backend.cpp.CppTargetCore;
import backend.js.JsTargetCore;
import backend.source.SourceTargetCommon;
import backend.vm.NekoTargetCore;

/** Unsupported runtime type operations must not replace or partially publish target files. */
class M14RuntimeTypeUnsupportedBackendIntegrationTest {
	static function main():Void {
		assertRejected('class Parent {}
class Main {
 static var selected:Class<Parent> = Parent;
 static function main():Void {}
}', "does not support runtime type operands");
		for (primitive in ["Int", "Float", "Bool"])
			assertRejected("class Main { static function main():Void { var selected = " + primitive + "; } }",
				"Neko primitive runtime predicate is not implemented");
		Sys.println("RUNTIME_TYPE_UNSUPPORTED_BACKENDS:PASS");
	}

	/** A rejected operation must leave the previous artifact and directory contents intact. */
	static function assertRejected(source:String, nekoDiagnostic:String):Void {
		final parsed = ParserStage.parse(source, "Main.hx");
		final resolved = new ResolvedModule("Main", "Main.hx", parsed);
		final index = TyperIndex.build([resolved]);
		final loader = new ModuleLoader(["."], new haxe.ds.StringMap<String>(), index, function(_):Bool return false);
		loader.markResolvedAlready([resolved]);
		final module = TyperStage.typeResolvedModule(resolved, index, loader);
		final program = new MacroExpandedProgram([module], false);
		final root = ".tmp/runtime-type-unsupported-" + Date.now().getTime();
		sys.FileSystem.createDirectory(root);
		final checks:Array<{name:String, emit:BackendContext->Void}> = [
			{
				name: "js",
				emit: context -> {
					new JsTargetCore().emit(program, context);
				}
			},
			{
				name: "cpp",
				emit: context -> {
					CppTargetCore.emit(program, context);
				}
			},
			{
				name: "neko",
				emit: context -> {
					NekoTargetCore.emit(program, context);
				}
			},
			{
				name: "php",
				emit: context -> {
					SourceTargetCommon.emitPhpTarget(program, context);
				}
			},
			{
				name: "lua",
				emit: context -> {
					SourceTargetCommon.emitTarget(Lua, program, context);
				}
			},
			{
				name: "cs",
				emit: context -> {
					SourceTargetCommon.emitTarget(Cs, program, context);
				}
			},
			{
				name: "python",
				emit: context -> {
					SourceTargetCommon.emitTarget(Python, program, context);
				}
			},
			{
				name: "ocaml",
				emit: context -> {
					EmitterStage.emitToDir(program, context.outputDir);
				}
			}
		];
		for (check in checks) {
			final directory = root + "/" + check.name;
			sys.FileSystem.createDirectory(directory);
			final path = directory + "/existing";
			sys.io.File.saveContent(path, "previous-output\n");
			final defines = new haxe.ds.StringMap<String>();
			defines.set("hxhx_neko_source_only", "1");
			final context = new BackendContext(directory, path, "Main", false, false, defines);
			var diagnostic = "";
			try {
				check.emit(context);
			} catch (error:haxe.Exception) {
				diagnostic = error.message;
			}
			if (diagnostic.indexOf(check.name == "neko" ? nekoDiagnostic : "does not support runtime type operands") < 0)
				throw "backend did not reject the precise unsupported operation: " + check.name + ": " + diagnostic;
			if (sys.io.File.getContent(path) != "previous-output\n" || sys.FileSystem.readDirectory(directory).length != 1)
				throw "backend changed output before rejecting runtime type operands: " + check.name;
			sys.FileSystem.deleteFile(path);
			sys.FileSystem.deleteDirectory(directory);
		}
		sys.FileSystem.deleteDirectory(root);
	}
}
