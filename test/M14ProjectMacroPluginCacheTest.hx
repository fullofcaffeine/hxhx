import hxhx.macro.ProjectMacroPluginCache;
import sys.FileSystem;
import sys.io.File;

/**
	hxhx builds, caches, and rebuilds a project's macro plugin by itself.

	`ProjectMacroPluginCache.ensure` is driven with a copy of the identity fixture
	(`test/fixtures/project-macro-identity`). The child compiler is the Stage3 compiler run by the
	interpreter (`M14ProjectMacroPluginTestCompiler`), and `dune` builds the real `.cma` and `.cmxs`.
	The copy guards one helper with `#if macro`, so the plugin compiles only when its classpath is
	compiled in the macro context.

	Checks, in order:
	0. The macro classpaths of a request include its implicit working directory and exclude the
	   standard library, the bundled compiler sources, and the per-output `_gen_hx` directory.
	1. A missing `dune` and a mismatched OCaml version fail with one diagnostic before any build.
	2. The first `ensure` builds the plugin and writes a receipt naming its sources and artifacts.
	3. A second `ensure` reuses it (a cache hit) without starting a compiler.
	4. While another process holds the build lock and no receipt exists, `ensure` waits and then
	   reports the lock.
	5. Editing the macro class rebuilds the plugin under a new plugin id, past a lock whose owner
	   process is gone, removes a temporary receipt left by an interrupted build, announces the
	   build once, and keeps the previous build for compiles that may still load it.
	6. A lock older than 30 minutes is stale; the next rebuild removes builds older than the previous one.

	Loading the plugin needs an OCaml-native hxhx; `scripts/hxhx/run-project-macro-module-smoke.sh`
	covers that end to end.
**/
class M14ProjectMacroPluginCacheTest {
	static function require(condition:Bool, message:String):Void {
		if (!condition)
			throw message;
	}

	static function expectFailure(label:String, run:Void->Void, expected:String):Void {
		try {
			run();
		} catch (error:String) {
			require(error.indexOf(expected) >= 0, label + ": expected `" + expected + "`, got: " + error);
			return;
		}
		throw label + ": expected a failure";
	}

	static function ocamlVersion():String {
		final process = new sys.io.Process("ocamlopt", ["-version"]);
		final version = StringTools.trim(process.stdout.readAll().toString());
		process.close();
		return version;
	}

	static function main():Void {
		final repo = haxe.io.Path.normalize(Sys.getCwd());
		final root = repo + "/.tmp/m14-project-macro-plugin-cache-" + Std.string(Std.int(haxe.Timer.stamp() * 1000));
		final src = root + "/src";
		FileSystem.createDirectory(src);
		final fixture = repo + "/test/fixtures/project-macro-identity/src";
		final identity = StringTools.replace(File.getContent(fixture + "/Identity.hx"), "\tstatic function require(",
			"\t#if macro\n\tstatic function require(");
		final macroOnly = StringTools.replace(identity, "\tstatic function functionOf(", "\t#end\n\n\tstatic function functionOf(");
		require(macroOnly.indexOf("#if macro") >= 0 && macroOnly.indexOf("#end") >= 0, "the fixture copy lost its macro-only guard");
		File.saveContent(src + "/Identity.hx", macroOnly);

		final cacheRoot = root + "/cache";
		final progress = new Array<String>();
		final version = ocamlVersion();
		function request(?dune:String, ?ocaml:String, ?lockTimeout:Float):ProjectMacroPluginRequest {
			return {
				declarations: ["Identity.preserve"],
				macroClassPaths: [src],
				classPaths: [src],
				defines: [],
				cwd: repo,
				supportClassPath: repo + "/packages/hxhx-core/src",
				runtimeSourceDirectories: [repo + "/packages/reflaxe.ocaml/std/runtime", repo + "/packages/hxhx-core/shims"],
				cacheRoot: cacheRoot,
				compilerIdentity: "m14-project-macro-plugin-cache",
				ocamlVersion: ocaml == null ? version : ocaml,
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
				dune: dune == null ? "dune" : dune,
				ocamlopt: "ocamlopt",
				artifactKind: "native",
				lockTimeoutSeconds: lockTimeout == null ? 900 : lockTimeout,
				buildTimeoutSeconds: 900,
				progress: line -> progress.push(line)
			};
		}

		// 0. The request's classpaths: the implicit working directory is a macro classpath; the
		// standard library, the compiler's bundled sources, and the per-output _gen_hx are not.
		final lists = hxhx.Stage3ProjectMacroPlugins.classPathsFor([
			"/p/src",
			"/p/out/_gen_hx",
			"/p",
			"/__hxhx_bundled_sources__/abc/ocaml/_std",
			"/std/ocaml/_std",
			"/std"
		], "/p/out/_gen_hx", "/std");
		require(lists.keyClassPaths.join("|") == "/p/src|/p|/__hxhx_bundled_sources__/abc/ocaml/_std|/std/ocaml/_std|/std",
			"unexpected key classpaths: " + lists.keyClassPaths);
		require(lists.macroClassPaths.join("|") == "/p/src|/p", "unexpected macro classpaths: " + lists.macroClassPaths);

		// 1. Toolchain diagnostics come before any build work.
		expectFailure("missing dune", () -> ProjectMacroPluginCache.ensure(request("hxhx-test-missing-dune")),
			"project macros need `dune` and the OCaml native compiler (`ocamlopt`) on PATH");
		expectFailure("OCaml version", () -> ProjectMacroPluginCache.ensure(request(null, "0.0.0")),
			"must be built by the OCaml version that built this hxhx (0.0.0)");

		// 2. Cold build.
		final coldStart = Sys.time();
		final cold = ProjectMacroPluginCache.ensure(request());
		final coldSeconds = Sys.time() - coldStart;
		switch cold.outcome {
			case Built(reason):
				require(reason.indexOf("no cached plugin") >= 0, "unexpected cold build reason: " + reason);
			case Reused:
				throw "the first ensure reused a plugin";
		}
		require(StringTools.startsWith(cold.activation.pluginId, "hxhx.project-macro."), "unexpected plugin id " + cold.activation.pluginId);
		require(StringTools.endsWith(cold.activation.artifactPath, ".cmxs") && FileSystem.exists(cold.activation.artifactPath),
			"the native plugin is missing: " + cold.activation.artifactPath);
		final receipt = File.getContent(cold.receiptPath);
		require(receipt.indexOf(src + "/Identity.hx") >= 0, "the receipt does not bind the macro source:\n" + receipt);
		require(receipt.indexOf("MacroSyntaxWire.hx") >= 0, "the receipt does not bind the plugin support sources:\n" + receipt);

		// 3. Warm reuse.
		final warmStart = Sys.time();
		final warm = ProjectMacroPluginCache.ensure(request());
		final warmSeconds = Sys.time() - warmStart;
		require(warm.outcome.match(Reused), "the second ensure did not reuse the plugin");
		require(warm.activation.pluginId == cold.activation.pluginId
			&& warm.cacheKey == cold.cacheKey, "the warm hit returned another plugin");

		// 4. A held lock makes a missing receipt wait, then report the lock.
		final keyDirectory = haxe.io.Path.directory(cold.receiptPath);
		final savedReceipt = cold.receiptPath + ".saved";
		FileSystem.rename(cold.receiptPath, savedReceipt);
		FileSystem.createDirectory(keyDirectory + "/.lock");
		File.saveContent(keyDirectory + "/.lock/owner", hxhxmacrohost.NativeMacroModuleHostIdentity.processId() + "\n");
		expectFailure("held lock", () -> ProjectMacroPluginCache.ensure(request(null, null, 0.5)), "waiting for another hxhx process");
		FileSystem.deleteFile(keyDirectory + "/.lock/owner");
		FileSystem.deleteDirectory(keyDirectory + "/.lock");
		FileSystem.rename(savedReceipt, cold.receiptPath);
		require(ProjectMacroPluginCache.ensure(request()).outcome.match(Reused), "the restored receipt was not reused");
		require(progress.filter(line -> line.indexOf("waiting for another hxhx process") >= 0).length == 1,
			"the lock wait was not announced: " + progress.join(" | "));

		// 5. Editing the macro class rebuilds it, even past a lock left by an interrupted build whose
		// process is gone, and the previous build stays for compiles that already validated it.
		final deadPid = {
			final process = new sys.io.Process("/bin/sh", ["-c", "echo $$"]);
			final pid = Std.parseInt(StringTools.trim(process.stdout.readAll().toString()));
			process.exitCode();
			process.close();
			pid;
		};
		require(deadPid != null && !hxhx.macro.ProjectMacroPluginProcess.isAlive(deadPid), "the finished shell is still alive");
		FileSystem.createDirectory(keyDirectory + "/.lock");
		File.saveContent(keyDirectory + "/.lock/owner", deadPid + "\n");
		File.saveContent(cold.receiptPath + ".interrupted.tmp", "{");
		File.saveContent(src + "/Identity.hx", macroOnly + "\n// edited\n");
		progress.resize(0);
		final edited = ProjectMacroPluginCache.ensure(request(null, null, 5));
		switch edited.outcome {
			case Built(reason):
				require(reason.indexOf("macro source changed since the plugin was built") >= 0, "unexpected rebuild reason: " + reason);
			case Reused:
				throw "an edited macro class reused the old plugin";
		}
		require(progress.length == 1 && progress[0].indexOf("building project macro plugin for Identity.preserve") >= 0,
			"the build was not announced exactly once: " + progress.join(" | "));
		require(edited.cacheKey == cold.cacheKey, "an edit changed the cache key instead of the receipt");
		require(edited.activation.pluginId != cold.activation.pluginId, "the rebuilt plugin kept the old plugin id");
		require(FileSystem.exists(cold.activation.artifactPath), "the previous build was removed while it may still be loading");
		require(!FileSystem.exists(cold.receiptPath + ".interrupted.tmp"), "a temporary receipt of an interrupted build was left behind");
		require(ProjectMacroPluginCache.ensure(request()).outcome.match(Reused), "the rebuilt plugin was not reused");

		// 6. A lock older than 30 minutes is stale even when its process id is alive (a reused id).
		FileSystem.createDirectory(keyDirectory + "/.lock");
		File.saveContent(keyDirectory + "/.lock/owner", hxhxmacrohost.NativeMacroModuleHostIdentity.processId() + "\n");
		final touch = new sys.io.Process("touch", ["-t", "200001010000", keyDirectory + "/.lock/owner"]);
		require(touch.exitCode() == 0, "could not age the lock");
		touch.close();
		File.saveContent(src + "/Identity.hx", macroOnly + "\n// edited twice\n");
		final again = ProjectMacroPluginCache.ensure(request(null, null, 5));
		require(again.outcome.match(Built(_)), "an old lock blocked the rebuild");
		require(!FileSystem.exists(cold.activation.artifactPath), "builds older than the previous one were kept");
		require(FileSystem.exists(edited.activation.artifactPath), "the previous build was removed");

		Sys.println("project_macro_plugin_cold_seconds=" + Math.round(coldSeconds * 10) / 10);
		Sys.println("project_macro_plugin_warm_seconds=" + Math.round(warmSeconds * 1000) / 1000);
		Sys.println("PROJECT_MACRO_PLUGIN_CACHE:PASS");
	}
}
