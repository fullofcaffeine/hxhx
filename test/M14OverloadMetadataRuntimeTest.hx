import backend.BackendContext;
import backend.js.JsBackend;

/** Calls selected from metadata must reach the real JavaScript host with unchanged values. */
class M14OverloadMetadataRuntimeTest {
	static function run(command:String, arguments:Array<String>):{code:Int, stdout:String, stderr:String} {
		final process = new sys.io.Process(command, arguments);
		final stdout = process.stdout.readAll().toString();
		final stderr = process.stderr.readAll().toString();
		final code = process.exitCode();
		process.close();
		return {code: code, stdout: stdout, stderr: stderr};
	}

	static function check(condition:Bool, message:String):Void {
		if (!condition)
			throw message;
	}

	static function main():Void {
		final root = ".tmp/overload_metadata_runtime";
		sys.FileSystem.createDirectory(root);
		final declarations = '@:native("String") extern class Host {'
			+ '@:overload(function(code:String):String {}) public static function fromCharCode(code:Int):String; }'
			+ '@:native("console") extern class Console {public static function log(value:String):Void;}';
		final source = declarations
			+ 'class Main {static function main():Void {'
			+ 'Console.log(Host.fromCharCode("65")); Console.log(Host.fromCharCode(66));}}';
		final path = root + "/Main.hx";
		sys.io.File.saveContent(path, source);
		final expected = "A\nB\n";
		final upstream = run("node_modules/.bin/haxe", ["-cp", root, "-main", "Main", "-js", root + "/upstream.js"]);
		check(upstream.code == 0, "upstream rejected the overload runtime fixture: " + upstream.stderr);
		final reference = run("node", [root + "/upstream.js"]);
		check(reference.code == 0 && reference.stdout == expected, "upstream host result differs: " + reference.stderr);
		final module = new ResolvedModule("Main", path, ParserStage.parse(source, path));
		final typed = TyperStage.typeResolvedModule(module, TyperIndex.build([module]));
		final output = root + "/native.js";
		new JsBackend().emit(new MacroExpandedProgram([typed], false),
			new BackendContext(root, output, "Main", true, false, HxDefineMap.fromRawDefines(["js=1"])));
		final native = run("node", [output]);
		check(native.code == 0 && native.stdout == expected, "native metadata overload call differs: " + native.stderr);
		final invalid = declarations + 'class Main {static function main():Void {Host.fromCharCode(true);}}';
		sys.io.File.saveContent(path, invalid);
		check(run("node_modules/.bin/haxe", ["-cp", root, "-main", "Main", "-js", root + "/invalid.js"]).code != 0,
			"upstream accepted the unlisted Boolean overload");
		var rejected = false;
		try {
			final broken = new ResolvedModule("Main", path, ParserStage.parse(invalid, path));
			TyperStage.typeResolvedModule(broken, TyperIndex.build([broken]));
		} catch (error:TyperError) {
			rejected = true;
		}
		check(rejected, "an unlisted argument type silently acquired an overload");
		Sys.println("OVERLOAD_METADATA_RUNTIME:PASS");
	}
}
