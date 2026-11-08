import haxe.io.Path;
import hxhx.macro.ProjectMacroPluginCache;
import sys.FileSystem;
import sys.io.File;

/**
	A project macro written with reification builds as a native plugin and computes, natively,
	the expression upstream Haxe computes.

	Fixture: `test/fixtures/project-macro-reification`. `Macros.build` assembles its result with
	`macro { ... }` and the splices `$b{}`, `$v{}`, `$e{}`, `$a{}`, a field splice and `@:pos`.
	`Shadowing` quotes where locals, parameters, and fields are named `haxe`, `Std`, and
	`hxhxmacrohost`, the roots of the lowered syntax, and quotes beside an import alias named `Std`
	and in a package with its own `Std` class and `haxe` sub-package; the probe prints those results too.

	1. Oracles: upstream Haxe 4.3.7 runs `Main` (`expected.stdout`) and `Probe` in its macro
	   context (`probe-expected.stdout`).
	2. Native: a copy of the fixture with a `Main` that calls `Probe.main()` is compiled with the
	   Stage3 emitter and run; it must print `probe-expected.stdout`. Before this lowering the
	   emitter stopped at the first quote.
	3. Plugin: `ProjectMacroPluginCache.ensure` builds the plugin for `Macros.tally` with the
	   interpreter-run child compiler and `dune`, exactly as a native hxhx does.

	Loading the plugin and running `Main` through it needs a native hxhx;
	`scripts/hxhx/run-project-macro-module-smoke.sh` covers that.
**/
class M14ProjectMacroReificationTest {
	static final fixture = "test/fixtures/project-macro-reification";

	static function require(condition:Bool, message:String):Void {
		if (!condition)
			throw message;
	}

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

	static function ocamlVersion():String {
		final process = new sys.io.Process("ocamlopt", ["-version"]);
		final version = StringTools.trim(process.stdout.readAll().toString());
		process.close();
		return version;
	}

	static function main():Void {
		final repo = Path.normalize(Sys.getCwd());
		final root = repo + "/.tmp/m14-project-macro-reification-" + Std.string(Std.int(haxe.Timer.stamp() * 1000));
		final src = root + "/src";
		deleteRecursive(root);
		FileSystem.createDirectory(src);
		FileSystem.createDirectory(src + "/shadow/haxe");
		for (name in [
			"Macros.hx",
			"Probe.hx",
			"Shadowing.hx",
			"AliasQuotes.hx",
			"shadow/Std.hx",
			"shadow/PackageQuotes.hx",
			"shadow/haxe/Marker.hx"
		])
			File.copy(fixture + "/src/" + name, src + "/" + name);
		// `$v{}` on an array or nullable calls the plugin support module. A plugin build reaches it
		// through its support classpath (`packages/hxhx-core/src`); the copy mirrors that classpath
		// for the probe program, whose harness compiles from one root.
		FileSystem.createDirectory(src + "/hxhxmacrohost");
		File.copy("packages/hxhx-core/src/hxhxmacrohost/MacroReificationValues.hx", src + "/hxhxmacrohost/MacroReificationValues.hx");

		// 1. Upstream oracles.
		final expected = File.getContent(fixture + "/expected.stdout");
		final probeExpected = File.getContent(fixture + "/probe-expected.stdout");
		M14Stage3RuntimeFixture.observe({
			command: "node_modules/.bin/haxe",
			arguments: ["-cp", fixture + "/src", "-main", "Main", "--interp"],
			expected: expected
		});
		M14Stage3RuntimeFixture.observe({
			command: "node_modules/.bin/haxe",
			arguments: ["-cp", fixture + "/src", "--macro", "Probe.main()", "--no-output"],
			expected: probeExpected
		});
		Sys.println("M14_PROJECT_MACRO_REIFICATION_ORACLE:PASS");

		// 2. The reified result, computed natively.
		final mainSource = "class Main {\n\tstatic function main():Void {\n\t\tProbe.main();\n\t}\n}\n";
		final mainPath = src + "/Main.hx";
		File.saveContent(mainPath, mainSource);
		final program = M14Stage3RuntimeFixture.prepareProgram({source: mainSource, path: mainPath, root: src});
		final executable = EmitterStage.emitToDir(new MacroExpandedProgram(program, false), root + "/out");
		M14Stage3RuntimeFixture.observe({command: executable, arguments: [], expected: probeExpected});
		Sys.println("M14_PROJECT_MACRO_REIFICATION_NATIVE:PASS");

		// 3. The plugin for the macro builds through the cache driver.
		final progress = new Array<String>();
		final built = ProjectMacroPluginCache.ensure({
			declarations: ["Macros.tally"],
			macroClassPaths: [src],
			classPaths: [src],
			defines: [],
			cwd: repo,
			supportClassPath: repo + "/packages/hxhx-core/src",
			runtimeSourceDirectories: [repo + "/packages/reflaxe.ocaml/std/runtime", repo + "/packages/hxhx-core/shims"],
			cacheRoot: root + "/cache",
			compilerIdentity: "m14-project-macro-reification",
			ocamlVersion: ocamlVersion(),
			compiler: {
				program: "haxe",
				leadingArgs: [
					"-cp",
					"test",
					"-cp",
					"packages/hxhx-core/src",
					"-cp",
					"packages/hxhx/src",
					"-cp",
					"packages/reflaxe.ocaml/src",
					"-D",
					"reflaxe",
					"--run",
					"M14ProjectMacroPluginTestCompiler"
				]
			},
			dune: "dune",
			ocamlopt: "ocamlopt",
			artifactKind: "native",
			lockTimeoutSeconds: 900,
			buildTimeoutSeconds: 900,
			progress: line -> progress.push(line)
		});
		switch built.outcome {
			case Built(_):
			case Reused:
				throw "the first ensure reused a plugin";
		}
		require(StringTools.endsWith(built.activation.artifactPath, ".cmxs") && FileSystem.exists(built.activation.artifactPath),
			"the native plugin is missing: " + built.activation.artifactPath);
		final receipt = File.getContent(built.receiptPath);
		require(receipt.indexOf("Macros.tally") >= 0, "the receipt does not name the macro declaration");
		Sys.println("M14_PROJECT_MACRO_REIFICATION_PLUGIN:PASS");

		deleteRecursive(root);
		Sys.println("M14_PROJECT_MACRO_REIFICATION:PASS");
	}
}
