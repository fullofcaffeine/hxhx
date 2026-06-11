class M14Stage3LuaRunSupportIntegrationTest {
	static function assertTrue(condition:Bool, message:String):Void {
		if (!condition)
			throw message;
	}

	static function runChild(mode:String):String {
		Sys.putEnv("HXHX_LUA_RUN_SUPPORT_MODE", mode);
		final proc = new sys.io.Process("haxe", ["test/m14_stage3_lua_run_support_child.hxml"]);
		final stdout = proc.stdout.readAll().toString();
		final stderr = proc.stderr.readAll().toString();
		final code = proc.exitCode();
		proc.close();
		Sys.putEnv("HXHX_LUA_RUN_SUPPORT_MODE", "");
		if (code != 0)
			throw "child `" + mode + "` failed with " + code + "\nstdout:\n" + stdout + "\nstderr:\n" + stderr;
		return StringTools.trim(stdout);
	}

	static function main():Void {
		final cmdStdout = runChild("cmd");
		assertTrue(cmdStdout == "lua-stdout:runner.lua alpha", "expected command-only Lua stdout, got `" + cmdStdout + "`");

		final runStdout = runChild("run");
		assertTrue(runStdout == "lua-stdout:artifact.lua alpha beta", "expected --run Lua stdout/args, got `" + runStdout + "`");
	}
}
