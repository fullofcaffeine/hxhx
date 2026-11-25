import hxhx.CompilationRequestContext;
import hxhx.Stage3Compiler;
import sys.FileSystem;
import sys.io.File;

/**
	An open record literal passed to an enum constructor emits natively (haxe_ocaml-areu3).

	Upstream's `UnitBuilder.hx` writes `var func = {args: [], ret: null, params: [], expr: ...}`
	and then `FFun(func)`. hxhx types `[]` as an Array of an unknown element, and the Stage3
	emitter refused every record operand with an unknown component. An open part may now stay
	open where its destination field stores a reference (Array, structure, class, enum, String,
	or a nullable reference). There the record carrier keeps the value's own `Obj.t`.

	- `test/fixtures/stage3_enum_open_record` must print what haxe 4.3.7 prints
	  (`expected.stdout`).
	- An open part at an `Int` destination is still rejected, with a message that names the field.
**/
class M14Stage3EnumOpenRecordTest {
	static inline final FIXTURE = "test/fixtures/stage3_enum_open_record";

	static function main():Void {
		final expected = File.getContent(FIXTURE + "/expected.stdout");
		require(run("node_modules/.bin/haxe", ["-cp", FIXTURE, "--run", "Main"]) == expected, "upstream output differs from expected.stdout");

		final root = haxe.io.Path.normalize(".tmp/m14_stage3_enum_open_record_" + Std.string(Date.now().getTime()));
		FileSystem.createDirectory(root);
		final built = compile(root + "/fixture", FIXTURE);
		require(built.code == 0, "the fixture must build:\n" + built.output);
		final actual = run(root + "/fixture/out/out.exe", []);
		require(actual == expected, "hxhx output differs from haxe 4.3.7:\n" + actual);

		final source = root + "/scalar/src";
		FileSystem.createDirectory(source);
		File.saveContent(source + "/Main.hx", [
			"typedef Counter = {count:Int};",
			"",
			"enum Box {",
			"	BCount(counter:Counter);",
			"}",
			"",
			"class Main {",
			"	static function main() {",
			"		var values = [];",
			"		var counter = {count: values[0]};",
			"		switch BCount(counter) {",
			"			case BCount(value): Sys.println(value.count);",
			"		}",
			"	}",
			"}"
		].join("\n"));
		final rejected = compile(root + "/scalar", source);
		require(rejected.code != 0 && rejected.output.indexOf("OCaml record enum argument cannot store open field `count` as Int") >= 0,
			"an open part at an Int destination must be rejected by name:\n" + rejected.output);

		deleteRecursive(root);
		Sys.println("M14_STAGE3_ENUM_OPEN_RECORD:PASS");
	}

	static function compile(out:String, source:String):{code:Int, output:String} {
		final context = new CompilationRequestContext(0, true, false);
		final code = Stage3Compiler.runRequest(["--hxhx-no-run", "--hxhx-out", out + "/out", "-cp", source, "-main", "Main"], context);
		final text = context.output.events().map(event -> event.text).join("");
		context.close(code == 0);
		return {code: code, output: text};
	}

	static function run(command:String, arguments:Array<String>):String {
		final process = new sys.io.Process(command, arguments);
		final output = process.stdout.readAll().toString();
		final errors = process.stderr.readAll().toString();
		final code = process.exitCode();
		process.close();
		require(code == 0, command + " exited " + code + ": " + errors);
		return output;
	}

	static function require(condition:Bool, message:String):Void {
		if (!condition)
			throw message;
	}

	static function deleteRecursive(path:String):Void {
		if (!FileSystem.exists(path))
			return;
		if (FileSystem.isDirectory(path)) {
			for (entry in FileSystem.readDirectory(path))
				deleteRecursive(path + "/" + entry);
			FileSystem.deleteDirectory(path);
		} else {
			FileSystem.deleteFile(path);
		}
	}
}
