import backend.BackendContext;
import backend.cpp.CppTargetCore;
import backend.source.SourceTargetCommon;
import backend.vm.NekoTargetCore;
import hxhx.Stage1Compiler.Stage1Args;

/**
	Unsupported runtime type operations must not replace or partially publish target files.
	JavaScript's admitted nominal operations and rejected core objects are exercised
	together by M14JsRuntimeTypeOperandsTest in the same required package command.
 */
class M14RuntimeTypeUnsupportedBackendIntegrationTest {
	static function main():Void {
		assertRejected('class Parent {}
class Main {
 static var selected:Class<Parent> = Parent;
 static function main():Void {}
}', "does not support runtime type operands");
		for (primitive in ["Int", "Float", "Bool"])
			assertRejected("class Main { static function main():Void { var selected = " + primitive + "; } }", null);
		// Discarding a type object must not hide an unsupported operand from the
		// publication guard. Its exact occurrence survives in either sequence child.
		for (body in ["Parent; 1;", "1; Parent;"])
			assertRejected("class Parent {} class Main { static function main():Void { var selected = { " + body + " }; } }", null);
		Sys.println("RUNTIME_TYPE_UNSUPPORTED_BACKENDS:PASS");
	}

	/** A rejected operation must leave the previous artifact and directory contents intact. */
	static function assertRejected(source:String, nekoDiagnostic:Null<String>):Void {
		final parsed = ParserStage.parse(source, "Main.hx");
		final resolved = new ResolvedModule("Main", "Main.hx", parsed);
		final arguments = Stage1Args.parse(["-main", "Main"], true);
		if (arguments == null)
			throw "rejection fixture could not discover the standard library";
		final defines = new haxe.ds.StringMap<String>();
		final paths = [Stage1Args.getStandardLibraryRoot(arguments)];
		// Load actual core declarations: incomplete Class<T> storage is not evidence
		// that a backend rejected the intended runtime-type operation.
		final index = TyperIndex.buildHeaders([resolved]);
		final loader = new ModuleLoader(paths, defines, index);
		loader.markResolvedAlready([resolved]);
		final pending = [resolved];
		final modules = new Array<TypedModule>();
		var cursor = 0;
		while (cursor < pending.length) {
			modules.push(TyperStage.typeResolvedModule(pending[cursor++], index, loader, true));
			for (loaded in loader.drainNewModules())
				pending.push(loaded);
		}
		final module = modules[0];
		for (owner in module.getBackendProjection().getClasses())
			for (initializer in owner.getFieldInitializers())
				if (initializer.getField().getType().hasUnknownComponent() || initializer.getField().getType().isUnresolved())
					throw "rejection fixture requires complete field types";
		final program = new MacroExpandedProgram(modules, false);
		final root = ".tmp/runtime-type-unsupported-" + Date.now().getTime();
		sys.FileSystem.createDirectory(root);
		final checks:Array<{name:String, emit:BackendContext->Void}> = [
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
			if (check.name == "neko" && nekoDiagnostic == null)
				continue;
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
