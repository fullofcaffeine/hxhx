import backend.BackendContext;
import backend.cpp.CppTargetCore;
import backend.source.SourceTargetCommon;
import backend.vm.NekoTargetCore;
import hxhx.Stage1Compiler.Stage1Args;

/**
	Unsupported runtime type operations must not replace or partially publish target files.
	C++ class descriptors execute natively; primitive meta-values still reject.
	JavaScript's admitted nominal operations and rejected core objects are exercised
	together by M14JsRuntimeTypeOperandsTest in the same required package command.
 */
class M14RuntimeTypeUnsupportedBackendIntegrationTest {
	static var serial:Int = 0;
	static final cppMetaDiagnostic = "managed class value requires an explicit meta-value representation";

	static function main():Void {
		assertInferredProvider("class Parent {} class Main { static function main():Void { var selected = Parent; } }", "Class");
		assertInferredProvider("enum Choice { One; } class Main { static function main():Void { var selected = Choice; } }", "Enum");
		assertAdmission('class Parent {}
class Main {
 static var selected:Class<Parent> = Parent;
 static function main():Void {}
}', "does not support runtime type operands", true);
		for (primitive in ["Int", "Float", "Bool"])
			assertAdmission("class Main { static function main():Void { var selected = " + primitive + "; } }", null);
		// Discarding a type object must not hide an unsupported operand from the
		// publication guard. Its exact occurrence survives in either sequence child.
		for (body in ["Parent; 1;", "1; Parent;"])
			assertAdmission("class Parent {} class Main { static function main():Void { var selected = { " + body + " }; } }", null, true);
		assertAdmission("class Parent {} class Main { static function main():Void { var selected = Parent; } }", null, true);
		for (body in ["Int; 1;", "1; Int;"])
			assertAdmission("class Main { static function main():Void { var selected = { " + body + " }; } }", null);
		assertCppSequence();
		Sys.println("RUNTIME_TYPE_UNSUPPORTED_BACKENDS:PASS");
	}

	/** Keep the real lazy dependency closure, including providers introduced by inferred value types. */
	static function program(source:String):MacroExpandedProgram {
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
		return new MacroExpandedProgram(modules, false);
	}

	/** A class or enum value must discover its meta-type without an explicit source annotation. */
	static function assertInferredProvider(source:String, expected:String):Void {
		final modules = program(source).getTypedModules();
		if (!Lambda.exists(modules, module -> module.getSourceOrigin().sourceModulePath == expected
			&& !module.getSourceOrigin().isSynthetic))
			throw "inferred runtime value did not load its real provider: " + expected;
	}

	/** A rejected operation must leave the previous artifact and directory contents intact. */
	static function assertAdmission(source:String, nekoDiagnostic:Null<String>, cppSupported:Bool = false):Void {
		final program = program(source);
		final root = ".tmp/runtime-type-unsupported-" + Date.now().getTime() + "-" + serial++;
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
			if (check.name == "cpp" && cppSupported) {
				assertCppExecution(program, directory);
				continue;
			}
			final path = directory + "/existing";
			sys.io.File.saveContent(path, "previous-output\n");
			final defines = new haxe.ds.StringMap<String>();
			defines.set("hxhx_neko_source_only", "1");
			final context = new BackendContext(directory, path, "Main", false, defines);
			var diagnostic = "";
			try {
				check.emit(context);
			} catch (error:haxe.Exception) {
				diagnostic = error.message;
			}
			final expected = check.name == "neko" ? nekoDiagnostic : check.name == "cpp" ? cppMetaDiagnostic : "does not support runtime type operands";
			if (diagnostic.indexOf(expected) < 0)
				throw "backend did not reject the precise unsupported operation: " + check.name + ": " + diagnostic;
			if (sys.io.File.getContent(path) != "previous-output\n" || sys.FileSystem.readDirectory(directory).length != 1)
				throw "backend changed output before rejecting runtime type operands: " + check.name;
			sys.FileSystem.deleteFile(path);
			sys.FileSystem.deleteDirectory(directory);
		}
		if (sys.FileSystem.readDirectory(root).length == 0)
			sys.FileSystem.deleteDirectory(root);
	}

	/** Accepted descriptors must build and execute, rather than merely escaping a rejection guard. */
	static function assertCppExecution(program:MacroExpandedProgram, directory:String):Void {
		final result = CppTargetCore.emit(program, new BackendContext(directory, null, "Main", true, new haxe.ds.StringMap()));
		if (!result.builtExecutable)
			throw "supported runtime type input did not build a native executable";
		final process = new sys.io.Process(result.entryPath, []);
		final stdout = process.stdout.readAll().toString();
		final stderr = process.stderr.readAll().toString();
		final code = process.exitCode();
		process.close();
		if (code != 0 || stdout != "" || stderr != "")
			throw "runtime class value execution failed: " + stdout + stderr;
	}

	/** Independently check descriptor identity and effects on both sides of a discarded class value. */
	static function assertCppSequence():Void {
		final source = "class Parent {} class Main {"
			+ "static var effects:Int = 0; static function step():Int { effects += 1; return effects; }"
			+ "static function main():Void { var selected = Parent; var first = { Parent; step(); };"
			+ "var last = { step(); Parent; }; if (first != 1 || effects != 2 || selected != last) throw 'runtime class sequence changed'; }}";
		final directory = ".tmp/runtime-type-sequence";
		sys.FileSystem.createDirectory(directory);
		sys.io.File.saveContent(directory + "/Main.hx", source);
		if (Sys.command("haxe", ["-cp", directory, "--run", "Main"]) != 0)
			throw "upstream runtime class sequence contract failed";
		assertCppExecution(program(source), directory + "/native");
		Sys.println("CPP_RUNTIME_TYPE_SEQUENCE:PASS");
	}
}
