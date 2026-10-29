import sys.io.File;
import sys.FileSystem;

/** Imported and aliased catches must keep resolved identity across both control paths. */
class M14JsCatchIdentityRuntimeTest {
	public static function run():Void {
		final root = JsRuntimeFixture.reserveOutput();
		final sources = [
			{name: "left.Fault", source: 'package left; class Fault { public function new() {} }'},
			{name: "right.Fault", source: 'package right; class Fault { public function new() {} }'},
			{name: "left.Child", source: 'package left; class Child extends Fault {}'},
			{name: "Main",
				source: 'import left.Fault; import right.Fault as Other; class Main {'
				+ 'static function main():Void {'
				+ 'var result = 0; try { throw new Fault(); } catch(e:Other) { result = 99; } catch(e:Fault) { result = 1; }'
				+ 'if (result != 1) throw "statement catch identity";'
				+ 'final value = try { throw new Other(); 0; } catch(e:Fault) { 99; } catch(e:Other) { 2; };'
				+ 'if (value != 2) throw "expression catch identity";'
				+ 'final inherited = try { throw new left.Child(); 0; } catch(e:Other) { 99; } catch(e:Fault) { 3; };'
				+ 'if (inherited != 3) throw "subclass catch identity";'
				+ '}}'}
		];
		final resolved = new Array<ResolvedModule>();
		for (entry in sources) {
			final path = root + "/" + entry.name.split(".").join("/") + ".hx";
			FileSystem.createDirectory(haxe.io.Path.directory(path));
			File.saveContent(path, entry.source);
			resolved.push(new ResolvedModule(entry.name, path, ParserStage.parse(entry.source, path)));
		}
		command("haxe", ["-cp", root, "-main", "Main", "-js", root + "/upstream.js"]);
		command("node", [root + "/upstream.js"]);
		Sys.println("JS_CATCH_IDENTITY_UPSTREAM:PASS");
		final index = TyperIndex.build(resolved);
		final typed = [for (module in resolved) TyperStage.typeResolvedModule(module, index)];
		JsRuntimeFixture.assertProgramRuntime(MacroStage.expandProgram(typed, []), "Main", "");
		Sys.println("JS_CATCH_IDENTITY_RUNTIME:PASS");
		@:privateAccess JsRuntimeFixture.removeOutput(root);
	}

	/** Bound child commands and reject unexpected output as well as failed assertions. */
	static function command(executable:String, args:Array<String>):Void {
		final process = new sys.io.Process(Sys.systemName() == "Mac" ? "gtimeout" : "timeout", ["30", executable].concat(args));
		final out = process.stdout.readAll().toString();
		final err = process.stderr.readAll().toString();
		final code = process.exitCode();
		process.close();
		if (code != 0 || out != "" || err != "")
			throw "catch identity observer: " + code + ": " + out + err;
	}
}
