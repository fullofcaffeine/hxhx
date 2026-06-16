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
		assertTrue(cmdStdout == "lua-stdout:runner.lua alpha\nstage3=cmd_ok", "expected command-only Lua stdout and marker, got `" + cmdStdout + "`");

		final runStdout = runChild("run");
		assertTrue(runStdout == "lua-stdout:artifact.lua alpha beta", "expected --run Lua stdout/args, got `" + runStdout + "`");

		final nekoCmdStdout = runChild("neko-cmd");
		assertTrue(nekoCmdStdout == "neko-stdout:bin/main.n", "expected post-emit Neko --cmd stdout only, got `" + nekoCmdStdout + "`");

		final sep = Sys.systemName() == "Windows" ? ";" : ":";
		final nekoPathStdout = runChild("neko-cmd-path");
		assertTrue(nekoPathStdout == "neko-stdout:bin/main.n\nneko-path:lib/ndll/Linux64/" + sep + "existing-neko-path",
			"expected post-emit Neko --cmd to prepend NEKOPATH, got `" + nekoPathStdout + "`");

		final collectStdout = runChild("collect-neko-ndll");
		assertTrue(collectStdout.indexOf("/dummy_ndll/ndll/") >= 0, "expected Neko ndll discovery output, got `" + collectStdout + "`");

		final resolverStdout = runChild("library-resolver-haxelib-always");
		assertTrue(resolverStdout == "resolver=always", "expected haxelib --always resolver fallback, got `" + resolverStdout + "`");

		final lixResolverStdout = runChild("library-resolver-lix-scoped-miss");
		assertTrue(lixResolverStdout == "resolver=lix-scoped-miss",
			"expected Lix scoped metadata miss to fall through to haxelib --always, got `" + lixResolverStdout + "`");
	}
}
