import haxe.io.Path;
import sys.FileSystem;
import sys.io.File;

/**
	Builds a file-system program with the Stage3 native emitter and compares it with upstream Haxe.

	Why
	- Stage3 output contains generated `Sys_io_File` and `Sys_FileSystem` OCaml
	  modules built from the standard `sys.io.File` and `sys.FileSystem`
	  classes. Their methods have no Haxe body, so each one is an empty stub in
	  the generated module. Only calls spelled with the short imported names
	  (`File.getContent`) reached the OCaml runtime; a fully qualified call such
	  as `sys.io.File.getContent(path)` bound to the stub. The stub returned a
	  placeholder that was not a string, so reading the result crashed the
	  native program.

	What
	- `stage3_sys_file_ops` creates, writes, reads, lists, renames, copies, and
	  deletes files and directories through both spellings and prints every
	  result.
	- The native executable must print exactly what upstream Haxe 4.3.7 prints.
	- A bodiless standard method without a native adapter must stop emission
	  with a named error rather than reach a stub.
**/
class M14Stage3SysFileOpsTest {
	static function deleteRecursive(path:String):Void {
		if (!FileSystem.exists(path))
			return;
		if (FileSystem.isDirectory(path)) {
			for (entry in FileSystem.readDirectory(path))
				deleteRecursive(Path.join([path, entry]));
			FileSystem.deleteDirectory(path);
			return;
		}
		FileSystem.deleteFile(path);
	}

	static function compareWithUpstream(label:String, source:String, expectedPath:String):Void {
		final path = source + "/Main.hx";
		final expected = File.getContent(expectedPath);
		M14Stage3RuntimeFixture.observe({command: "node_modules/.bin/haxe", arguments: ["-cp", source, "--run", "Main"], expected: expected});
		final outDir = ".tmp/m14_stage3_sys_file_ops_" + label;
		deleteRecursive(outDir);
		final program = M14Stage3RuntimeFixture.prepareProgram({source: File.getContent(path), path: path, root: source});
		final executable = EmitterStage.emitToDir(new MacroExpandedProgram(program, false), outDir);
		M14Stage3RuntimeFixture.observe({command: executable, arguments: [], expected: expected});
		deleteRecursive(outDir);
		Sys.println("M14_STAGE3_SYS_FILE_OPS_" + label.toUpperCase() + ":PASS");
	}

	/**
		Emit an inline program whose only call has no Haxe body and no native
		adapter, and require the named emit-time error instead of an executable.
	**/
	static function rejectStubCall(label:String, source:String, expected:String, ?helpers:Map<String, String>):Void {
		final root = ".tmp/m14_stage3_sys_file_ops_reject_" + label;
		deleteRecursive(root);
		FileSystem.createDirectory(root + "/src");
		final path = root + "/src/Main.hx";
		File.saveContent(path, source);
		if (helpers != null)
			for (name => helper in helpers)
				File.saveContent(root + "/src/" + name + ".hx", helper);
		final program = M14Stage3RuntimeFixture.prepareProgram({source: source, path: path, root: root + "/src"});
		var message:Null<String> = null;
		try {
			EmitterStage.emitToDir(new MacroExpandedProgram(program, false), root + "/out");
		} catch (error:String) {
			message = error;
		}
		// A request that stops early leaves per-request emitter state behind;
		// the compiler request pipeline clears it the same way.
		EmitterStage.resetRequestState();
		deleteRecursive(root);
		if (message == null || message.indexOf(expected) < 0)
			throw "expected emit-time stub rejection containing <" + expected + ">, got <" + message + ">";
		Sys.println("M14_STAGE3_SYS_FILE_OPS_REJECT_" + label.toUpperCase() + ":PASS");
	}

	static function main():Void {
		compareWithUpstream("whole_file", "test/fixtures/stage3_sys_file_ops", "test/fixtures/stage3_sys_file_ops/expected.stdout");
		// `FileSystem.stat` returns a `sys.FileStat` record that the runtime does
		// not build in the Stage3 representation yet, so it has no adapter.
		rejectStubCall("std_stat",
			"class Main {\n"
			+ "\tstatic function main():Void {\n"
			+ "\t\tSys.println(sys.FileSystem.stat(\".\").size);\n"
			+ "\t}\n"
			+ "}\n",
			"sys.FileSystem.stat has no native adapter; the generated Sys_FileSystem module only has an empty stub for it");
		// A project extern without a native binding gets the same generated stub.
		rejectStubCall("project_extern", "class Main {\n"
			+ "\tstatic function main():Void {\n"
			+ "\t\tSys.println(Native.greeting());\n"
			+ "\t}\n"
			+ "}\n",
			"Native.greeting has no native adapter; the generated Native module only has an empty stub for it", [
				"Native" => "extern class Native {\n\tpublic static function greeting():String;\n}\n"
			]);
	}
}
