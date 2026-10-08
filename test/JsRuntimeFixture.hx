import backend.BackendContext;
import backend.js.JsBackend;
import sys.FileSystem;
import sys.io.File;

/** Execute a typed module through the JavaScript backend and retain failed output for inspection. */
function assertRuntime(typed:TypedModule, module:String, expected:String, ?nodeArguments:Array<String>):Void {
	final output = reserveOutput();
	final script = output + "/main.js";
	new JsBackend().emit(MacroStage.expandProgram([typed], []),
		new BackendContext(output, script, module, true, false, HxDefineMap.fromRawDefines(["js=1", "js-es=5"])));
	final arguments = ["60", "node"].concat(nodeArguments == null ? [] : nodeArguments).concat([script]);
	final process = new sys.io.Process(Sys.systemName() == "Mac" ? "gtimeout" : "timeout", arguments);
	final stdout = process.stdout.readAll().toString();
	final stderr = process.stderr.readAll().toString();
	final code = process.exitCode();
	process.close();
	if (code != 0 || stdout != expected)
		throw "JavaScript runtime differs; retained " + output + ": " + stdout + stderr;
	removeOutput(output);
}

/**
	Reserve an output directory atomically, including across separate Haxe processes.
	The host mktemp tool creates the directory before returning it; timestamps alone
	can collide and let one successful fixture remove another fixture's artifact.
 */
function reserveOutput():String {
	FileSystem.createDirectory(".tmp");
	final process = new sys.io.Process("mktemp", ["-d", ".tmp/js_runtime_fixture_XXXXXX"]);
	final output = StringTools.trim(process.stdout.readAll().toString());
	final errors = process.stderr.readAll().toString();
	final code = process.exitCode();
	process.close();
	if (code != 0 || output.length == 0)
		throw "cannot reserve JavaScript fixture output: " + errors;
	return output;
}

/** Remove only the successful fixture's allocated output directory. */
private function removeOutput(path:String):Void {
	if (FileSystem.isDirectory(path)) {
		for (entry in FileSystem.readDirectory(path))
			removeOutput(path + "/" + entry);
		FileSystem.deleteDirectory(path);
	} else {
		FileSystem.deleteFile(path);
	}
}
