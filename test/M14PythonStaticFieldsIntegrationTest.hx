import backend.BackendContext;
import backend.BackendRegistry;
import backend.source.PythonFieldAccessLowering;
import haxe.ds.StringMap;
import haxe.io.Path;
import sys.FileSystem;
import sys.io.File;
import HxExpr;

/** Compile typed field ownership to Python and observe mutation without relying on generated spelling. */
class M14PythonStaticFieldsIntegrationTest {
	static function module(source:String, path:String):TypedModule {
		final resolved = new ResolvedModule("Main", path, ParserStage.parse(source, path));
		return TyperStage.typeResolvedModule(resolved, TyperIndex.build([resolved]));
	}

	static function mainProjection(typed:TypedModule, name:String):TypedBackendFunctionProjection {
		for (cls in typed.getBackendProjection().getClasses())
			if (HxClassDecl.getName(cls.getDeclaration()) == "Main")
				for (fn in cls.getFunctions())
					if (HxFunctionDecl.getName(fn.getDeclaration()) == name)
						return fn;
		throw "missing constructor observer function " + name;
	}

	static function output(command:String, arguments:Array<String>):String {
		final process = new sys.io.Process(command, arguments);
		final stdout = process.stdout.readAll().toString();
		final stderr = process.stderr.readAll().toString();
		final code = process.exitCode();
		process.close();
		if (code != 0)
			throw command + " constructor observer failed: " + stderr;
		return stdout;
	}

	/** The selected construction owns its arguments; equal-looking syntax cannot borrow that selection. */
	static function constructors(root:String):Void {
		final source = 'class Holder {
 public var value:Int;
 public function new(value:Int) this.value = value;
}
class Pair {
 public var value:Int;
 public function new(first:Holder, second:Holder) value = first.value * 10 + second.value;
}
class Main {
 static var calls:Int = 0;
 static function next():Int { calls++; return calls; }
 static function build():Holder return new Holder(9);
 static function main() {
  var pair = new Pair(new Holder(next()), new Holder(next()));
  Sys.println(pair.value);
  Sys.println(calls);
  var nested = new Holder(new Holder(next()).value + 4);
  Sys.println(nested.value);
  Sys.println(calls);
 }
}';
		final directory = Path.join([root, "constructors"]);
		FileSystem.createDirectory(directory);
		final path = Path.join([directory, "Main.hx"]);
		File.saveContent(path, source);
		final typed = module(source, path);
		final program = new MacroExpandedProgram([typed], false);
		final projection = mainProjection(typed, "main");
		final originalBody = HxFunctionDecl.getBody(projection.getDeclaration());
		final before = TypedBodyFingerprint.exactStatements(originalBody);
		final occurrence = projection.getConstructorCatalog().getEntries()[0];
		if (occurrence.getConstructedType().getNominalIdentity().getCanonicalName() != "Main.Pair")
			throw "constructor observer lost its exact secondary owner";
		for (invalid in [occurrence.getExpression(), ENew("Main.Pair", occurrence.getArguments())]) {
			final owner = invalid == occurrence.getExpression() ? mainProjection(module(source, path), "main") : projection;
			var rejected = false;
			try {
				owner.requireConstructor(invalid);
			} catch (failure:haxe.Exception) {
				rejected = failure.message.indexOf("absent from the current function projection") >= 0;
			}
			if (!rejected)
				throw "constructor observer accepted a foreign or rebuilt occurrence";
		}
		final lowered = new PythonFieldAccessLowering(program).body(projection);
		final names = [
			for (expression in TypedConstructorSource.inStatements(lowered))
				switch expression {
					case ENew(name, _):
						name;
					case _:
						throw "unexpected parent construction";
				}
		];
		if (names.join(",") != "Pair,Holder,Holder,Holder,Holder" || TypedBodyFingerprint.exactStatements(originalBody) != before)
			throw "Python constructor lowering changed ownership or its original projection";
		final build = mainProjection(typed, "build");
		final unmapped = new PythonFieldAccessLowering(new MacroExpandedProgram([], false)).body(build);
		if (TypedBodyFingerprint.exactStatements(unmapped) != TypedBodyFingerprint.exactStatements(HxFunctionDecl.getBody(build.getDeclaration())))
			throw "Python guessed an emitted class for an absent owner";
		final probe = module('class Main { static function probe() {
 var syntax = macro new Main.Holder(99); var values = new Array<Int>();
} } class Holder { public function new(value:Int) {} }', path);
		final probeFunction = mainProjection(probe, "probe");
		final probeBefore = TypedBodyFingerprint.exactStatements(HxFunctionDecl.getBody(probeFunction.getDeclaration()));
		if (TypedBodyFingerprint.exactStatements(new PythonFieldAccessLowering(new MacroExpandedProgram([probe], false)).body(probeFunction)) != probeBefore)
			throw "Python constructor lowering changed quoted syntax or a core constructor";
		final expected = "12\n2\n7\n3\n";
		output("haxe", [
			"-cp",
			directory,
			"-main",
			"Main",
			"-python",
			Path.join([directory, "upstream.py"])
		]);
		if (output("python3", [Path.join([directory, "upstream.py"])]) != expected)
			throw "upstream constructor order or effects differ from the authored expectation";
		final context = new BackendContext(directory, Path.join([directory, "candidate.py"]), "Main", true, false, new StringMap<String>());
		final emitted = BackendRegistry.createForTarget("python-native").emit(program, context);
		if (output("python3", [emitted.entryPath]) != expected)
			throw "Python changed nested constructor argument order or evaluation count";
		Sys.println("PYTHON_CONSTRUCTOR_OWNERSHIP:PASS");
	}

	static function main():Void {
		final fixture = Path.join([Sys.getCwd(), "test", "python_static_fields"]);
		final sourcePath = Path.join([fixture, "Main.hx"]);
		final resolved = new ResolvedModule("Main", sourcePath, ParserStage.parse(File.getContent(sourcePath), sourcePath));
		final index = TyperIndex.build([resolved]);
		final loader = new ModuleLoader([fixture], new StringMap<String>(), index, function(_):Bool return false);
		loader.markResolvedAlready([resolved]);
		final typed = TyperStage.typeResolvedModule(resolved, index, loader);
		final program = new MacroExpandedProgram([typed], false);
		final root = Path.join([Sys.getCwd(), ".tmp", "m14_python_static_fields"]);
		final context = new BackendContext(root, Path.join([root, "Main.py"]), "Main", true, false, new StringMap<String>());
		final emitted = BackendRegistry.createForTarget("python-native").emit(program, context);
		final process = new sys.io.Process("python3", [emitted.entryPath]);
		final stdout = process.stdout.readAll().toString();
		final stderr = process.stderr.readAll().toString();
		final code = process.exitCode();
		process.close();
		if (code != 0)
			throw "Python static field fixture failed: " + stderr;
		if (stdout != File.getContent(Path.join([fixture, "expected.stdout"])))
			throw "Python changed field/local ownership or update count: " + stdout;
		Sys.println("PYTHON_STATIC_FIELDS:PASS");
		constructors(root);
	}
}
