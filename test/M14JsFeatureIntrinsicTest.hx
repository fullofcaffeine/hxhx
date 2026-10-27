import sys.io.File;
import haxe.io.Path;
import backend.BackendContext;
import backend.js.JsBackend;

/** Feature-selected source blocks must survive shared typing before JavaScript lowering. */
class M14JsFeatureIntrinsicTest {
	static function main():Void {
		final root = Path.normalize(Sys.getCwd() + "/test/fixtures/js_feature_intrinsic");
		final resolution = new CompilerSourceProvider().resolveModule([root], "Main");
		final path = resolution.filePath;
		if (path == null)
			throw "feature fixture did not resolve";
		final resolved = new ResolvedModule("Main", path, ParserStage.parse(File.getContent(path), path), resolution.toOrigin("Main"));
		final typed = TyperStage.typeResolvedModule(resolved, TyperIndex.build([resolved]));
		final program = MacroStage.expandProgram([typed], [{name: "Probe", source: "let value = 1"}]);
		for (mode in ["default", "full", "std", "no"]) {
			final defines = HxDefineMap.fromRawDefines(mode == "default" ? ["js=1"] : ["js=1", "dce=" + mode]);
			final prepared = hxhx.Stage3JsPreparation.prepare({
				program: program,
				classPaths: [root],
				standardRoot: root + "/origin_lib",
				main: "Main",
				defines: defines
			});
			if (prepared.getSelectedRuntimeFeatures().indexOf("probe.enabled") < 0 || prepared.getGeneratedOcamlModules().length != 1)
				throw "preparation discarded selected features or generated module metadata";
			final backends = [new JsBackend(), JsBackend.providerRegistrations()[0].create()];
			for (index in 0...backends.length) {
				final backend = backends[index];
				final output = ".tmp/js_feature_preparation_" + Date.now().getTime() + "_" + mode + "_" + index;
				sys.FileSystem.createDirectory(output);
				final script = output + "/main.js";
				backend.emit(prepared, new BackendContext(output, script, "Main", false, defines));
				final process = new sys.io.Process(Sys.systemName() == "Mac" ? "gtimeout" : "timeout", ["60", "node", script]);
				final stdout = process.stdout.readAll().toString();
				final stderr = process.stderr.readAll().toString();
				final exit = process.exitCode();
				process.close();
				if (exit != 0 || stdout != "enabled\nbranch\nabsent\n")
					throw "selected feature behavior differs: " + stdout + stderr;
			}
		}
		Sys.println("JS_FEATURE_INTRINSIC:PASS");
	}
}
