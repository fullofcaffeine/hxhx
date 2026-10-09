import sys.io.File;
import backend.BackendContext;
import backend.vm.NekoTargetCore;

/** Prove no-traces at shared typing and JavaScript/Neko runtime, using authored Haxe 4.3.7 behavior. */
class M14TraceDisabledTest {
	/** Successful observers are silent; retain artifacts if compilation or execution fails. */
	static function command(executable:String, arguments:Array<String>):Void {
		final child = new sys.io.Process(Sys.systemName() == "Mac" ? "gtimeout" : "timeout", ["30", executable].concat(arguments));
		final stdout = child.stdout.readAll().toString();
		final stderr = child.stderr.readAll().toString();
		final code = child.exitCode();
		child.close();
		if (code != 0 || stdout != "" || stderr != "")
			throw "disabled trace observer failed: " + executable + ": " + code + "\n" + stdout + stderr;
	}

	static function main():Void {
		final name = "TraceDisabled";
		final root = "test/fixtures/trace_call_contract";
		final path = root + "/" + name + ".hx";
		final resolved = new ResolvedModule(name, path, ParserStage.parse(File.getContent(path), path));
		for (target in ["js", "neko"]) {
			final index = TyperIndex.build([resolved]);
			final defines = new haxe.ds.StringMap<String>();
			defines.set("no-traces", "1");
			defines.set(target, "1");
			final loader = new ModuleLoader([root], defines, index, null, false);
			final typed = TyperStage.typeResolvedModule(resolved, index, loader);
			if (target == "js") {
				JsRuntimeFixture.assertRuntime(typed, name, "");
			} else {
				final output = JsRuntimeFixture.reserveOutput();
				final program = MacroStage.expandProgram([typed], []);
				final artifact = output + "/main";
				final context = new BackendContext(output, artifact + ".n", name, true, false, HxDefineMap.fromRawDefines(["neko=1", "no-traces=1"]));
				File.saveContent(artifact + ".neko", @:privateAccess NekoTargetCore.renderProgram(program, context));
				command("nekoc", [artifact + ".neko"]);
				command("neko", [artifact + ".n"]);
				sys.FileSystem.deleteFile(artifact + ".neko");
				sys.FileSystem.deleteFile(artifact + ".n");
				sys.FileSystem.deleteDirectory(output);
			}
			Sys.println("TRACE_DISABLED:PASS " + target);
		}
	}
}
