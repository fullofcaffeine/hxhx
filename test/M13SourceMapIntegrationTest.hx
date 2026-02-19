class M13SourceMapIntegrationTest {
	static function shQuote(s:String):String {
		if (s == null)
			return "''";
		return "'" + s.split("'").join("'\\''") + "'";
	}

	static function runHaxeCapture(args:Array<String>):{code:Int, output:String} {
		if (Sys.systemName() == "Windows") {
			// Best-effort: this repo's CI is POSIX-based; keep the test deterministic there.
			return {code: Sys.command("haxe", args), output: ""};
		}

		final cmd = "haxe " + args.map(shQuote).join(" ");
		final p = new sys.io.Process("sh", ["-lc", cmd + " 2>&1"]);
		final out = p.stdout.readAll().toString();
		final code = p.exitCode();
		p.close();
		return {code: code, output: out};
	}

	static function findLineOfNeedle(source:String, needle:String):Int {
		final idx = source.indexOf(needle);
		if (idx < 0)
			return -1;
		var line = 1;
		for (i in 0...idx)
			if (source.charCodeAt(i) == "\n".code)
				line++;
		return line;
	}

	static function main() {
		final outDir = "out_ocaml_m13_sourcemap_" + Std.string(Std.int(Date.now().getTime()));
		sys.FileSystem.createDirectory(outDir);

		final args = [
			"-cp",
			"test",
			"-main",
			"pkg.M13SourceMapFailMain",
			"--no-output",
			"-lib",
			"reflaxe.ocaml",
			"-D",
			"no-traces",
			"-D",
			"no_traces",
			"-D",
			"ocaml_output=" + outDir,
			"-D",
			"ocaml_build=byte",
			"-D",
			"ocaml_sourcemap=directives"
		];

		final res = runHaxeCapture(args);
		if (res.code == 0)
			throw "expected haxe to fail (dune build should fail) but exit code was 0";

		final srcPath = "test/pkg/M13SourceMapFailMain.hx";
		final src = sys.io.File.getContent(srcPath);
		final expectedLine = findLineOfNeedle(src, "__ocaml__");
		if (expectedLine <= 0)
			throw "failed to find __ocaml__ callsite line in " + srcPath;

		// We only assert on the basename + line number so this stays stable across environments.
		if (res.output.indexOf("M13SourceMapFailMain.hx") < 0) {
			throw "expected mapped error output to mention M13SourceMapFailMain.hx, got:\n" + res.output;
		}
		if (res.output.indexOf("line " + Std.string(expectedLine)) < 0) {
			throw "expected mapped error output to mention line " + expectedLine + ", got:\n" + res.output;
		}
	}
}
