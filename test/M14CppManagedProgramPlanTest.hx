import backend.BackendContext;
import backend.cpp.CppManagedProgramPlan;
import backend.cpp.CppTargetCore;
import backend.cpp.CppTypedProgramProjection;

/** Normal target admission must join exact declarations and leave output untouched on unsupported effects. */
class M14CppManagedProgramPlanTest {
	static function program(source:String):MacroExpandedProgram {
		final parsed = new ResolvedModule("Main", "Main.hx", ParserStage.parse(source, "Main.hx"));
		return new MacroExpandedProgram([TyperStage.typeResolvedModule(parsed, TyperIndex.build([parsed]))], false);
	}

	static function rejected(run:Void->Void, diagnostic:String):Void {
		try {
			run();
		} catch (failure:haxe.Exception) {
			if (failure.message.indexOf(diagnostic) >= 0)
				return;
			throw failure;
		}
		throw "managed program accepted unsupported input: " + diagnostic;
	}

	/** A failed target operation must not create its directory or overwrite an existing source. */
	static function admission(source:String, wanted:String, diagnostic:String, name:String, resources:Array<backend.BackendResource>):Void {
		final directory = ".tmp/managed-program-admission/" + name;
		sys.FileSystem.createDirectory(directory);
		final output = directory + "/Main.cpp";
		sys.io.File.saveContent(output, "retained prior source\n");
		final before = sys.FileSystem.readDirectory(directory);
		before.sort((left, right) -> left < right ? -1 : left > right ? 1 : 0);
		rejected(() -> CppTargetCore.emit(program(source), new BackendContext(directory, output, wanted, true, false, new haxe.ds.StringMap(), resources)),
			diagnostic);
		final after = sys.FileSystem.readDirectory(directory);
		after.sort((left, right) -> left < right ? -1 : left > right ? 1 : 0);
		if (sys.io.File.getContent(output) != "retained prior source\n" || before.join("\n") != after.join("\n"))
			throw "failed managed admission published an artifact";
	}

	static function main():Void {
		final main = new ResolvedModule("Main", "Main.hx", ParserStage.parse("class Main { static function main():Void { Sys.println('user'); } }", "Main.hx"));
		final authoredSys = new ResolvedModule("Sys", "Sys.hx",
			ParserStage.parse("class Sys { public static function println(value:Dynamic):Void {} }", "Sys.hx"));
		final index = TyperIndex.build([main, authoredSys]);
		final authored = new MacroExpandedProgram([
			TyperStage.typeResolvedModule(main, index),
			TyperStage.typeResolvedModule(authoredSys, index)
		], false);
		if (new CppManagedProgramPlan(new CppTypedProgramProjection(authored), "Main").render().indexOf("writeStdout(") >= 0)
			throw "authored Sys body was replaced with a native output operation";
		final source = "class Main { static function main():Void { Other.println(3); } } class Other { public static function println(value:Int):Int { return value + 1; } }";
		final projected = new CppTypedProgramProjection(program(source));
		final selected = new CppManagedProgramPlan(projected, "Main");
		final first = selected.render();
		if (first != selected.render() || first.indexOf("writeStdout(") >= 0 || first.indexOf("std::function") >= 0 || first.indexOf("std::shared_ptr") >= 0)
			throw "managed program changed identity or selected a name-based native binding";
		final unused = source + " class Unused { public static function dormant():Void { throw 'unreachable'; } }";
		if (first != new CppManagedProgramPlan(new CppTypedProgramProjection(program(unused)), "Main").render())
			throw "unreachable method changed managed program symbols";
		admission(source, "Missing", "one exact requested main", "missing-main", []);
		// Instance predicates are supported. Prove admission and the false result for null
		// through a native process; the remaining rejection cases still protect old output.
		final predicate = CppTargetCore.emit(program("class Main { static function main():Void { var value:Main = null; if (value is Main) throw 'null matched Main'; } }"),
			new BackendContext(".tmp/managed-program-admission/runtime-type", null, "Main", true, true, new haxe.ds.StringMap()));
		if (!predicate.builtExecutable)
			throw "instance predicate admission requires a native executable";
		final process = new sys.io.Process(predicate.entryPath, []);
		final stdout = process.stdout.readAll().toString();
		final stderr = process.stderr.readAll().toString();
		final code = process.exitCode();
		process.close();
		if (code != 0 || stdout != "" || stderr != "")
			throw "instance predicate admission changed null behavior: " + stdout + stderr;
		admission("class Main { static function main():Void {} } class Other { static function main():Void {} }", "", "one exact requested main",
			"ambiguous-main", []);
		admission("class Main { static var state:Float = 1.0; static function main():Void {} }", "Main", "explicit type contract", "static-initializer", []);
		admission("class Main { static function main():Void {} } class Unused { static var state:Float = 1.0; }", "Main", "explicit type contract",
			"uncalled-class-initializer", []);
		admission("class Main { static function main():Void {} } class Unused { static function __init__():Void { throw 1.0; } }", "Main",
			"managed rooted expression requires explicit lowering for EFloat", "uncalled-class-startup", []);
		admission("class Main { static function main():Void { Native.run(); } } extern class Native { public static function run():Void; }", "Main",
			"explicit native or instance binding", "native-binding", []);
		admission(source, "Main", "explicit resource publication", "resources", [{name: "sample", data: haxe.io.Bytes.ofString("content")}]);
		final owner = projected.getModules()[0].projection.getClasses()[0];
		owner.getFunctions()[0].getBody().push(SExpr(EInt(7), HxPos.unknown()));
		rejected(() -> selected.render(), "projection was mutated");
		Sys.println("CPP_MANAGED_PROGRAM_PLAN:PASS");
	}
}
