import haxe.macro.Expr;
import sys.io.File;

/**
	Same-name overloads of an abstract stay separate functions in authored parsing
	(haxe_ocaml-ac5i9.17).

	`haxe/ds/Vector.hx` declares two `extern overload` constructors. Haxe 4.3.7 keeps both fields.
	hxhx's declaration scanner returned both, but `ParserStage` added scanned members by name and
	dropped the second one, so the parse oracle saw only `new(length)`.

	Authored parsing (the parse oracle) now keeps every overload. The compile path keeps the first
	one only: the frozen Stage3 OCaml backend rejects an abstract with two constructor bodies, and
	making both visible waits for the single OCaml lowering (haxe_ocaml-95co6). The native check
	proves the compile path still builds an overloaded abstract.

	`expected.bodies.json` lists the bodies upstream's parse recorder printed for `Cells`, in
	declaration order.
**/
class M14AbstractOverloadSyntaxTest {
	static final root = "test/fixtures/abstract_overload_syntax";

	static function bodies(source:String, authored:Bool):Array<{key:String, body:String}> {
		final path = root + "/Main.hx";
		final decl = (authored ? ParserStage.parseAuthored(source, path) : ParserStage.parse(source, path)).getDecl();
		final export = new MacroBodyExport(new MacroSyntaxPositions(path));
		final position:Position = {file: path, min: 0, max: 0};
		for (cls in HxModuleDecl.getClasses(decl))
			if (HxClassDecl.getName(cls) == "Cells")
				return [
					for (fn in HxClassDecl.getFunctions(cls))
						if (HxFunctionDecl.getHasBody(fn)) {key: HxFunctionDecl.getName(fn), body: ParseOracleHxhx.functionBody(cls, fn, export, position)}
				];
		throw "missing abstract Cells";
	}

	static function describe(entries:Array<{key:String, body:String}>):String
		return [for (entry in entries) entry.key + ":\n" + entry.body].join("\n");

	static function observe(command:String, arguments:Array<String>, expected:String):Void {
		final process = new sys.io.Process(Sys.systemName() == "Mac" ? "gtimeout" : "timeout", ["60", command].concat(arguments));
		final stdout = process.stdout.readAll().toString();
		final stderr = process.stderr.readAll().toString();
		final code = process.exitCode();
		process.close();
		if (code != 0 || stdout != expected)
			throw "abstract overload observer differs: " + stdout + stderr;
	}

	public static function main():Void {
		final source = File.getContent(root + "/Main.hx");
		final expected:Array<{key:String, body:String}> = haxe.Json.parse(File.getContent(root + "/expected.bodies.json"));
		final authored = bodies(source, true);
		if (describe(authored) != describe(expected))
			throw "authored overloads differ:\nexpected:\n" + describe(expected) + "\nactual:\n" + describe(authored);
		Sys.println("ABSTRACT_OVERLOAD_AUTHORED:PASS");

		// The compile path keeps the first overload of each name, as before.
		final ordinary = [for (entry in bodies(source, false)) entry.key].join(",");
		if (ordinary != "new,sum,get_length")
			throw "ordinary parsing must keep the first overload only: " + ordinary;
		Sys.println("ABSTRACT_OVERLOAD_ORDINARY:PASS");

		observe("node_modules/.bin/haxe", ["-cp", root, "--run", "Main"], File.getContent(root + "/expected.stdout"));
		Sys.println("ABSTRACT_OVERLOAD_UPSTREAM_RUN:PASS");

		final nativeRoot = "test/fixtures/abstract_overload_native";
		final nativePath = nativeRoot + "/Main.hx";
		final nativeExpected = File.getContent(nativeRoot + "/expected.stdout");
		observe("node_modules/.bin/haxe", ["-cp", nativeRoot, "--run", "Main"], nativeExpected);
		final typed = M14Stage3RuntimeFixture.typeMain({source: File.getContent(nativePath), path: nativePath, root: nativeRoot});
		final executable = EmitterStage.emitToDir(MacroStage.expandProgram([typed], []), ".tmp/abstract_overload_native");
		observe(executable, [], nativeExpected);
		Sys.println("ABSTRACT_OVERLOAD_NATIVE:PASS");
	}
}
