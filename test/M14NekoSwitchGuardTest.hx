import sys.io.File;
import backend.BackendContext;
import backend.vm.NekoTargetCore;

/** Execute the shared guard contract through the real Neko providers and both artifact layouts. */
class M14NekoSwitchGuardTest {
	static function main():Void {
		final root = "test/fixtures/stage3_switch_guard";
		final output = ".tmp/neko-switch-guard";
		sys.FileSystem.createDirectory(output);
		final expected = File.getContent(root + "/expected.stdout");
		M14Stage3RuntimeFixture.observe({
			command: "node_modules/.bin/haxe",
			arguments: ["-cp", root, "-main", "Main", "-neko", output + "/upstream.n"],
			expected: ""
		});
		M14Stage3RuntimeFixture.observe({command: "neko", arguments: [output + "/upstream.n"], expected: expected});
		Sys.println("SWITCH_GUARD_NEKO_UPSTREAM:PASS");
		final started = Sys.time();
		final program = NekoSourceProgramFixture.build([{path: "Main.hx", source: File.getContent(root + "/Main.hx")}]);
		Sys.println("SWITCH_GUARD_NEKO_TYPED seconds=" + (Sys.time() - started));
		final functions = [
			for (module in program.getTypedModules())
				for (owner in module.getTypedClasses())
					for (fn in owner.getFunctions())
						fn
		];
		final revisions = functions.map(CompilerTypedTreeRevision.functionBody);
		final context = new BackendContext(output, output + "/local.n", "Main", false, HxDefineMap.fromRawDefines(["neko=1"]));
		final result = NekoTargetCore.emit(program, context);
		Sys.println("SWITCH_GUARD_NEKO_EMITTED seconds=" + (Sys.time() - started));
		M14Stage3RuntimeFixture.observe({command: "neko", arguments: [result.entryPath], expected: expected});
		Sys.println("SWITCH_GUARD_NEKO_SPLIT:PASS");
		File.saveContent(output + "/single.neko", @:privateAccess NekoTargetCore.renderProgram(program, context));
		M14Stage3RuntimeFixture.observe({command: "nekoc", arguments: [output + "/single.neko"], expected: ""});
		M14Stage3RuntimeFixture.observe({command: "neko", arguments: [output + "/single.n"], expected: expected});
		for (index in 0...functions.length)
			if (CompilerTypedTreeRevision.functionBody(functions[index]) != revisions[index])
				throw "Neko guarded switch emission changed authored source";
		Sys.println("SWITCH_GUARD_NEKO_SINGLE:PASS");
	}
}
