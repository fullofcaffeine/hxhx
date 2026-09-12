import haxe.io.Path;
import sys.FileSystem;
import sys.io.File;

/**
	Proves that typed instance calls retain their declaring class and receiver.
	A same-named static method must not change argument planning for another class.
	Native output checks dispatch and optional arguments; a negative case ensures
	the supplied receiver cannot fill a missing required source argument.
**/
class M14Stage3ExactCallOwnerIntegrationTest {
	static function removeTree(path:String):Void {
		if (!FileSystem.exists(path))
			return;
		if (FileSystem.isDirectory(path)) {
			for (entry in FileSystem.readDirectory(path))
				removeTree(Path.join([path, entry]));
			FileSystem.deleteDirectory(path);
		} else
			FileSystem.deleteFile(path);
	}

	static function check(missing:Bool):Void {
		final root = ".tmp/stage3-exact-call-owner-" + (missing ? "missing" : "valid");
		removeTree(root);
		FileSystem.createDirectory(root);
		final mainPath = Path.join([root, "Main.hx"]);
		final receiverPath = Path.join([root, "CallReceiver.hx"]);
		final call = missing ? "receiver.delay();" : "receiver.delay(7); receiver.optional(8);";
		final mainSource = "class Main { var receiver:CallReceiver; public function new() { receiver = new CallReceiver(); "
			+ call
			+ " } public static function delay(callback:()->Void, time:Int):Void { callback(); Sys.println(time); }"
			+ " static function main() { new Main(); delay(() -> Sys.println(\"static\"), 9); } }";
		final receiverSource = "class CallReceiver { public function new() {} public function delay(value:Int):Void { Sys.println(value); }"
			+ " public function optional(value:Int, ?label:String):Void { Sys.println(value); } }";
		File.saveContent(mainPath, mainSource);
		File.saveContent(receiverPath, receiverSource);
		var failure:Null<String> = null;
		try {
			final modules = [
				new ResolvedModule("Main", mainPath, ParserStage.parse(mainSource, mainPath)),
				new ResolvedModule("CallReceiver", receiverPath, ParserStage.parse(receiverSource, receiverPath))
			];
			final index = TyperIndex.build(modules);
			final typed = modules.map(module -> TyperStage.typeResolvedModule(module, index));
			final executable = EmitterStage.emitToDir(MacroStage.expandProgram(typed, []), Path.join([root, "out"]), true);
			if (missing)
				throw "missing source argument was accepted";
			final process = new sys.io.Process(executable, []);
			final stdout = process.stdout.readAll().toString();
			final stderr = process.stderr.readAll().toString();
			final code = process.exitCode();
			process.close();
			if (code != 0 || stdout != "7\n8\nstatic\n9\n")
				throw "wrong exact-call behavior: " + stdout + stderr;
		} catch (message:String) {
			failure = message;
		} catch (error:haxe.Exception) {
			failure = error.message;
		}
		removeTree(root);
		if (missing) {
			if (failure == null || failure.indexOf("missing required argument #1 (`value`)") < 0)
				throw "wrong missing-argument diagnostic: " + failure;
		} else if (failure != null)
			throw failure;
	}

	static function main():Void {
		check(false);
		check(true);
		Sys.println("M14_STAGE3_EXACT_CALL_OWNER:PASS");
	}
}
