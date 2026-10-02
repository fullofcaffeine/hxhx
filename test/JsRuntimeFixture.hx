import backend.BackendContext;
import backend.js.JsBackend;
import sys.FileSystem;
import sys.io.File;

/** Execute a typed module through the JavaScript backend and retain failed output for inspection. */
function assertRuntime(typed:TypedModule, module:String, expected:String):Void {
	final output = ".tmp/js_runtime_fixture_" + module + "_" + Std.string(Date.now().getTime());
	FileSystem.createDirectory(output);
	final script = output + "/main.js";
	new JsBackend().emit(MacroStage.expandProgram([typed], []),
		new BackendContext(output, script, module, true, false, HxDefineMap.fromRawDefines(["js=1", "js-es=5"])));
	final process = new sys.io.Process(Sys.systemName() == "Mac" ? "gtimeout" : "timeout", ["60", "node", script]);
	final stdout = process.stdout.readAll().toString();
	final stderr = process.stderr.readAll().toString();
	final code = process.exitCode();
	process.close();
	if (code != 0 || stdout != expected)
		throw "JavaScript runtime differs; retained " + output + ": " + stdout + stderr;
	removeOutput(output);
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
