import TyTypeDeclaration.TyTypeResolutionContext;

/** Structural intersection aliases retain their fields through typing and native execution. */
class M14StructuralIntersectionTest {
	static function check(condition:Bool, message:String):Void {
		if (!condition)
			throw message;
	}

	static function run(command:String, arguments:Array<String>):{code:Int, stdout:String, stderr:String} {
		final process = new sys.io.Process(command, arguments);
		final stdout = process.stdout.readAll().toString();
		final stderr = process.stderr.readAll().toString();
		final code = process.exitCode();
		process.close();
		return {code: code, stdout: stdout, stderr: stderr};
	}

	static function main():Void {
		final root = ".tmp/structural_intersection";
		sys.FileSystem.createDirectory(root);
		final path = root + "/Main.hx";
		final declarations = 'typedef Base<T>={value:T}; ' + 'typedef Combined<T>=Base<T> & {var ?label:String;}; '
			+ 'typedef Legacy<T>={>Base<T>, var ?label:String;}; ' + 'typedef Repeated=Base<Int> & {value:Int}; ';
		final source = declarations
			+ 'class Main { static function main():Void {'
			+ 'var item:Combined<Int>={value:7}; Sys.println(item.value);'
			+ 'var repeated:Repeated={value:9}; Sys.println(repeated.value); } }';
		sys.io.File.saveContent(path, source);
		final expected = "7\n9\n";
		final upstream = run("haxe", ["-cp", root, "--run", "Main"]);
		check(upstream.code == 0 && upstream.stdout == expected, "upstream structural intersection differs: " + upstream.stderr);
		final module = new ResolvedModule("Main", path, ParserStage.parse(source, path));
		final index = TyperIndex.build([module]);
		final context:TyTypeResolutionContext = {
			packagePath: "",
			modulePath: "Main",
			directives: [],
			filePath: path,
			position: HxPos.unknown(),
			parameters: []
		};
		final combined = index.resolveTypeUse(TyType.fromHintText("Combined<Int>"), context).getType();
		final legacy = index.resolveTypeUse(TyType.fromHintText("Legacy<Int>"), context).getType();
		check(combined.getSemanticKey() == legacy.getSemanticKey(), "intersection and structural extension disagree");
		final fields = combined.getAnonymousFields();
		check(fields.length == 2
			&& fields[0].name == "label"
			&& fields[0].isOptional
			&& !fields[0].type.isNullable()
			&& fields[1].name == "value"
			&& fields[1].type.getSemanticKey() == "primitive:Int",
			"intersection lost optionality, generic substitution, or field identity");
		final typed = TyperStage.typeResolvedModule(module, index);
		final executable = EmitterStage.emitToDir(MacroStage.expandProgram([typed], []), root + "/ocaml", true);
		final native = run(executable, []);
		check(native.code == 0 && native.stdout == expected, "native structural intersection differs: " + native.stderr);
		for (invalid in [
			'typedef Base={value:Int}; typedef Bad=Base & {value:String};',
			'class Base {public var value:Int;} typedef Bad=Base & {label:String};'
		]) {
			final text = invalid + 'class Main {static function main():Void {}}';
			sys.io.File.saveContent(path, text);
			check(run("haxe", ["-cp", root, "--run", "Main"]).code != 0, "upstream accepted invalid structural intersection");
			var rejected = false;
			try {
				TyperIndex.build([new ResolvedModule("Main", path, ParserStage.parse(text, path))]);
			} catch (error:TyperError) {
				rejected = true;
			}
			check(rejected, "invalid structural intersection silently overwrote or discarded a field");
		}
		Sys.println("STRUCTURAL_INTERSECTION:PASS");
	}
}
