import backend.BackendContext;
import backend.BackendRegistry;
import haxe.ds.StringMap;
import sys.io.File;

/** Compare real Lua class behavior with an independent expectation and upstream Haxe. */
class M14LuaNominalBodiesIntegrationTest {
	static function observe(command:String, arguments:Array<String>, expected:String):Void {
		final process = new sys.io.Process(command, arguments);
		final stdout = process.stdout.readAll().toString();
		final stderr = process.stderr.readAll().toString();
		final code = process.exitCode();
		process.close();
		if (code != 0)
			throw command + " failed with exit " + code + ": " + stderr;
		if (StringTools.trim(stdout) != StringTools.trim(expected))
			throw command + " nominal class output mismatch: " + stdout;
	}

	static function checkFixture(name:String, marker:String):Void {
		final fixture = "test/fixtures/" + name;
		final expected = File.getContent(fixture + "/expected.stdout");
		observe("haxe", ["-cp", fixture, "-main", "Main", "--interp"], expected);
		Sys.println(marker + "_UPSTREAM:PASS");
		final path = fixture + "/Main.hx";
		final resolved = new ResolvedModule("Main", path, ParserStage.parse(File.getContent(path), path));
		final index = TyperIndex.build([resolved]);
		final loader = new ModuleLoader([fixture], new StringMap<String>(), index, function(_):Bool return false);
		loader.markResolvedAlready([resolved]);
		final program = MacroStage.expandProgram([TyperStage.typeResolvedModule(resolved, index, loader, true)], []);
		final output = ".tmp/m14_" + name;
		final result = BackendRegistry.requireForTarget("lua-native")
			.emit(program, new BackendContext(output, output + "/Main.lua", "Main", true, false, new StringMap<String>()));
		observe("lua", [result.entryPath], expected);
		Sys.println(marker + "_NATIVE:PASS");
	}

	static function main():Void {
		checkFixture("lua_nominal_bodies", "LUA_NOMINAL");
		checkFixture("lua_try_transfers", "LUA_TRY_TRANSFERS");
	}
}
