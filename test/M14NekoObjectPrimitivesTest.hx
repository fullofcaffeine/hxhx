import backend.BackendContext;
import backend.vm.NekoTargetCore;
import sys.io.File;

/** Compare reserved VM aliases with local callable and value bindings in both native layouts. */
class M14NekoObjectPrimitivesTest {
	static function main():Void {
		final fixture = "test/fixtures/neko_object_primitives";
		final directory = ".tmp/neko_object_primitives";
		sys.FileSystem.createDirectory(directory);
		final sourcePath = fixture + "/Main.hx";
		final expected = File.getContent(fixture + "/expected.stdout");
		M14Stage3RuntimeFixture.observe({command: "haxe", arguments: ["-cp", fixture, "-main", "Main", "-neko", directory + "/upstream.n"], expected: ""});
		M14Stage3RuntimeFixture.observe({command: "neko", arguments: [directory + "/upstream.n"], expected: expected});
		final resolved = new ResolvedModule("Main", sourcePath, ParserStage.parse(File.getContent(sourcePath), sourcePath));
		final defines = HxDefineMap.fromRawDefines(["neko=1"]);
		final index = TyperIndex.buildHeaders([resolved]);
		final loader = new ModuleLoader([fixture], defines, index);
		loader.markResolvedAlready([resolved]);
		final program = MacroStage.expandProgram([TyperStage.typeResolvedModule(resolved, index, loader)], []);
		final context = new BackendContext(directory, directory + "/main.n", "Main", true, false, defines);
		final split = @:privateAccess NekoTargetCore.renderSplitProgram(program, context, directory + "/main.neko");
		File.saveContent(split.entryPath, split.entrySource);
		for (part in split.support)
			File.saveContent(part.path, part.source);
		File.saveContent(directory + "/single.neko", @:privateAccess NekoTargetCore.renderProgram(program, context));
		for (file in sys.FileSystem.readDirectory(directory))
			if (StringTools.endsWith(file, ".neko"))
				M14Stage3RuntimeFixture.observe({command: "nekoc", arguments: [directory + "/" + file], expected: ""});
		for (layout in ["main", "single"])
			M14Stage3RuntimeFixture.observe({command: "neko", arguments: [directory + "/" + layout + ".n"], expected: expected});
		Sys.println("NEKO_OBJECT_PRIMITIVES:PASS");
	}
}
