import sys.FileSystem;
import sys.io.File;

class M14RuntimeCallStackIntegrationTest {
	static function assertTrue(cond:Bool, message:String):Void {
		if (!cond)
			throw message;
	}

	static function assertContains(haystack:String, needle:String, label:String):Void {
		if (haystack.indexOf(needle) < 0)
			throw label + ": expected to find '" + needle + "'";
	}

	static function hasCommand(cmd:String):Bool {
		try {
			final p = new sys.io.Process(cmd, ["--version"]);
			final code = p.exitCode();
			p.close();
			return code == 0;
		} catch (_) {
			return false;
		}
	}

	static function deleteRecursive(path:String):Void {
		if (!FileSystem.exists(path))
			return;
		if (FileSystem.isDirectory(path)) {
			for (entry in FileSystem.readDirectory(path))
				deleteRecursive(haxe.io.Path.join([path, entry]));
			FileSystem.deleteDirectory(path);
		} else {
			FileSystem.deleteFile(path);
		}
	}

	static function exeNameFromOutDir(outDir:String):String {
		final base = haxe.io.Path.withoutDirectory(haxe.io.Path.normalize(outDir));
		final out = new StringBuf();
		for (i in 0...base.length) {
			final c = base.charCodeAt(i);
			final isAlphaNum = (c >= 97 && c <= 122) || (c >= 65 && c <= 90) || (c >= 48 && c <= 57);
			out.add(isAlphaNum ? String.fromCharCode(c) : "_");
		}
		var s = out.toString();
		if (s.length == 0)
			s = "ocaml_app";
		if (s.charCodeAt(0) >= 48 && s.charCodeAt(0) <= 57)
			s = "_" + s;
		return s.toLowerCase();
	}

	static function main():Void {
		final tmpRoot = haxe.io.Path.normalize('.tmp/m14_runtime_callstack_' + Std.string(Std.int(Date.now().getTime())));
		final srcDir = haxe.io.Path.join([tmpRoot, 'src']);
		final outDir = haxe.io.Path.join([tmpRoot, 'out']);
		deleteRecursive(tmpRoot);
		FileSystem.createDirectory(srcDir);
		FileSystem.createDirectory(outDir);

		final mainHx = haxe.io.Path.join([srcDir, 'Main.hx']);
		File.saveContent(mainHx, [
			'class Main {',
			'  static function main() {',
			'    final rendered = haxe.CallStack.toString(haxe.CallStack.callStack());',
			'    try {',
			'      throw new haxe.Exception("boom");',
			'    } catch (e:haxe.Exception) {',
			'      Sys.println("call_len=" + rendered.length);',
			'      Sys.println("detail_has_exception=" + (e.details().indexOf("Exception:") >= 0));',
			'    }',
			'  }',
			'}',
		].join("\n"));

		final args = [
			"-cp",
			srcDir,
			"-main",
			"Main",
			"--no-output",
			"-lib",
			"reflaxe.ocaml",
			"-D",
			"no-traces",
			"-D",
			"no_traces",
			"-D",
			"ocaml_no_build",
			"-D",
			"ocaml_output=" + outDir
		];
		final compileExit = Sys.command("haxe", args);
		assertTrue(compileExit == 0, "haxe compile failed: " + compileExit);

		final callStackMl = haxe.io.Path.join([outDir, 'haxe_CallStack.ml']);
		assertTrue(FileSystem.exists(callStackMl), "missing generated haxe_CallStack.ml");
		final ml = File.getContent(callStackMl);
		assertContains(ml, "HxBacktrace.callstack_lines", "generated CallStack should use HxBacktrace directly");
		assertTrue(ml.indexOf("Haxe_NativeStackTrace") < 0, "generated CallStack should not depend on Haxe_NativeStackTrace");
		final nativeStackTraceMl = haxe.io.Path.join([outDir, 'haxe_NativeStackTrace.ml']);
		assertTrue(FileSystem.exists(nativeStackTraceMl), "missing generated haxe_NativeStackTrace.ml");
		final nativeStackTraceOutput = File.getContent(nativeStackTraceMl);
		assertContains(nativeStackTraceOutput, "HxBacktrace.callstack_lines", "generated NativeStackTrace should use the typed HxBacktrace boundary");
		assertContains(nativeStackTraceOutput, "HxBacktrace.exceptionstack_lines",
			"generated NativeStackTrace should use the typed HxBacktrace exception boundary");
		final nativeStackTraceSource = File.getContent("packages/reflaxe.ocaml/std/ocaml/_std/haxe/NativeStackTrace.hx");
		assertTrue(nativeStackTraceSource.indexOf("untyped __ocaml__") < 0,
			"NativeStackTrace should not regain raw OCaml injection for the typed HxBacktrace API");

		if (hasCommand("dune") && hasCommand("ocamlc")) {
			final prev = Sys.getCwd();
			Sys.setCwd(outDir);
			final exeName = exeNameFromOutDir(outDir);
			final buildExit = Sys.command("dune", ["build", "./" + exeName + ".exe"]);
			Sys.setCwd(prev);
			assertTrue(buildExit == 0, "dune build failed: " + buildExit);

			final builtExe = haxe.io.Path.join([outDir, "_build", "default", exeName + ".exe"]);
			assertTrue(FileSystem.exists(builtExe), "missing built exe: " + builtExe);
			final outPath = haxe.io.Path.join([tmpRoot, 'stdout.log']);
			final runExit = Sys.command("sh", ["-c", "'" + builtExe + "' > '" + outPath + "'"]);
			assertTrue(runExit == 0, "built exe failed: " + runExit);
			final stdout = File.getContent(outPath);
			assertContains(stdout, "call_len=", "runtime should print call stack summary");
			assertContains(stdout, "detail_has_exception=true", "exception details should remain functional");
		}

		deleteRecursive(tmpRoot);
	}
}
