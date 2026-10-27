import sys.io.File;
import sys.FileSystem;
import backend.BackendContext;
import backend.vm.NekoTargetCore;

/** Prove no-traces at shared typing and JavaScript/Neko runtime, using authored Haxe 4.3.7 behavior. */
class M14TraceDisabledTest {
	/** Retain artifacts if compilation or the exact runtime observation fails. */
	static function command(executable:String, arguments:Array<String>, expected:String = ""):Void {
		final child = new sys.io.Process(Sys.systemName() == "Mac" ? "gtimeout" : "timeout", ["30", executable].concat(arguments));
		final stdout = child.stdout.readAll().toString();
		final stderr = child.stderr.readAll().toString();
		final code = child.exitCode();
		child.close();
		if (code != 0 || stdout != expected || stderr != "")
			throw "trace observer failed: " + executable + ": " + code + "\n" + stdout + stderr;
	}

	/** Execute generated Neko for the already typed logging policy and ordered operands. */
	public static function assertNeko(typed:TypedModule, name:String, expected:String, disabled:Bool = false):Void {
		final output = JsRuntimeFixture.reserveOutput();
		final program = MacroStage.expandProgram([typed], []);
		final artifact = output + "/main";
		final defines = disabled ? ["neko=1", "no-traces=1"] : ["neko=1"];
		final context = new BackendContext(output, artifact + ".n", name, false, HxDefineMap.fromRawDefines(defines));
		File.saveContent(artifact + ".neko", @:privateAccess NekoTargetCore.renderProgram(program, context));
		command("nekoc", [artifact + ".neko"]);
		command("neko", [artifact + ".n"], expected);
		FileSystem.deleteFile(artifact + ".neko");
		FileSystem.deleteFile(artifact + ".n");
		FileSystem.deleteDirectory(output);
	}

	static function main():Void {
		M14TraceControlTest.run();
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
				assertNeko(typed, name, "", true);
			}
			Sys.println("TRACE_DISABLED:PASS " + target);
		}
	}
}
