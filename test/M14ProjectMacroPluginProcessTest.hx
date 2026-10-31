import hxhx.macro.ProjectMacroPluginProcess;

/**
	The tool runner of project-macro plugin builds stops a tool and everything it started.

	A plugin build runs a child hxhx and `dune`, which start processes of their own. Each check
	starts a small shell tool through `ProjectMacroPluginProcess`:

	1. A tool that finishes normally returns its exit code and its merged output.
	2. At the time limit, the tool and a grandchild it started in the background are both gone, and
	   the result says it timed out.
	3. SIGINT to the wrapper (what Ctrl-C on the compile delivers) stops the tool promptly; a
	   non-interactive shell would otherwise leave a background tool ignoring SIGINT.
	4. A missing tool reports a non-zero code; a live process of another user counts as alive.
**/
class M14ProjectMacroPluginProcessTest {
	static final root = ".tmp/m14-project-macro-plugin-process";

	static function require(condition:Bool, message:String):Void {
		if (!condition)
			throw message;
	}

	static function readPid(path:String):Int {
		final pid = Std.parseInt(StringTools.trim(sys.io.File.getContent(path)));
		require(pid != null, "no pid in " + path);
		return pid;
	}

	static function main():Void {
		sys.FileSystem.createDirectory(root);
		final echo = ProjectMacroPluginProcess.run("/bin/sh", ["-c", "echo out; echo err >&2; exit 3"], 10);
		require(echo.code == 3 && !echo.timedOut && echo.output.indexOf("out") >= 0 && echo.output.indexOf("err") >= 0,
			"unexpected normal run: "
			+ echo.code
			+ " "
			+ echo.output);

		final grandchildFile = root + "/grandchild.pid";
		final started = Sys.time();
		final slow = ProjectMacroPluginProcess.run("/bin/sh", ["-c", "sleep 25 & echo $! > " + grandchildFile + "; wait"], 1);
		require(slow.timedOut, "the slow tool was not reported as timed out");
		require(Sys.time() - started < 20, "the timeout did not stop the tool promptly");
		require(!ProjectMacroPluginProcess.isAlive(readPid(grandchildFile)), "a grandchild outlived the timeout");

		final toolFile = root + "/tool.pid";
		final launched = ProjectMacroPluginProcess.launch("/bin/sh", ["-c", "echo $$ > " + toolFile + "; sleep 30"], 60);
		var waited = 0;
		while (!sys.FileSystem.exists(toolFile) && waited < 100) {
			Sys.sleep(0.1);
			waited++;
		}
		final tool = readPid(toolFile);
		ProjectMacroPluginProcess.run("kill", ["-INT", Std.string(launched.process.getPid())], 5);
		final interrupted = Sys.time();
		ProjectMacroPluginProcess.finish(launched);
		require(Sys.time() - interrupted < 10, "the interrupted wrapper did not finish promptly");
		require(!ProjectMacroPluginProcess.isAlive(tool), "the tool survived SIGINT to its wrapper");

		require(ProjectMacroPluginProcess.run("hxhx-test-missing-tool", [], 5).code != 0, "a missing tool reported success");
		require(ProjectMacroPluginProcess.isAlive(1), "a live process of another user (pid 1) was not reported alive");
		Sys.println("PROJECT_MACRO_PLUGIN_PROCESS:PASS");
	}
}
