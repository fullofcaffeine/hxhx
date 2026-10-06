import backend.BackendContext;
import backend.cpp.CppTargetCore;
import backend.js.JsTargetCore;
import backend.source.JavaSourceTargetCore;
import backend.source.PhpSourceTargetCore;
import backend.source.SourceMvpTargetCore;
import backend.vm.NekoTargetCore;

/** Native execution must discard Void effects without hiding an authored local. */
class M14SequencingNativeIntegrationTest {
	static function main():Void {
		final requested = Sys.args();
		final target = requested.length == 0 ? "cpp" : requested[0];
		if (["cpp", "js", "neko", "python", "php", "java", "lua"].indexOf(target) < 0)
			throw "unknown sequencing target: " + target;
		final localOnly = requested.length > 1 && requested[1] == "local";
		final root = "test/oracle/" + (localOnly ? "sequencing_local_seed" : "sequencing_producer_seed");
		final path = root + "/src/Main.hx";
		final resolved = new ResolvedModule("Main", path, ParserStage.parse(sys.io.File.getContent(path), path));
		final typed = TyperStage.typeResolvedModule(resolved, TyperIndex.build([resolved]));
		final program = new MacroExpandedProgram([typed], false);
		final context = new BackendContext(".tmp/sequencing-producer-" + target + (localOnly ? "-local" : ""), null, "Main", true, true,
			new haxe.ds.StringMap<String>());
		final result = switch (target) {
			case "js": new JsTargetCore().emit(program, context);
			case "neko": NekoTargetCore.emit(program, context);
			case "python": SourceMvpTargetCore.emit(Python, program, context);
			case "php": PhpSourceTargetCore.emit(program, context);
			case "java": JavaSourceTargetCore.emit(program, context);
			case "lua": SourceMvpTargetCore.emit(Lua, program, context);
			case _: CppTargetCore.emit(program, context);
		};
		if (target == "cpp" && !result.builtExecutable)
			throw "sequencing test requires a native executable";
		if (!sys.FileSystem.exists(result.entryPath))
			throw "sequencing target did not emit its executable input";
		final command = switch (target) {
			case "js": "node";
			case "neko", "php", "java", "lua": target;
			case "python": "python3";
			case _: result.entryPath;
		};
		final arguments = switch (target) {
			case "cpp": [];
			case "java": ["-jar", result.entryPath];
			case _: [result.entryPath];
		};
		final process = new sys.io.Process(command, arguments);
		final stdout = process.stdout.readAll().toString();
		final stderr = process.stderr.readAll().toString();
		final code = process.exitCode();
		process.close();
		if (code != 0 || stdout != sys.io.File.getContent(root + "/expected.stdout"))
			throw "native sequencing behavior differs: " + stdout + stderr;
		Sys.println("SEQUENCING_PRODUCER_NATIVE:PASS target=" + target);
	}
}
