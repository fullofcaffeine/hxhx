class M8ModuleAliasesIntegrationTest {
	static function assertContains(haystack:String, needle:String, label:String):Void {
		if (haystack.indexOf(needle) < 0) {
			throw label + ": expected to find '" + needle + "'";
		}
	}

	static function main() {
		final outDir = "out_ocaml_m8_aliases_" + Std.string(Std.int(Date.now().getTime()));
		sys.FileSystem.createDirectory(outDir);

		final args = [
			"-cp", "test",
			"-main", "M8AliasesMain",
			"--no-output",
			"-lib", "reflaxe.ocaml",
			"-D", "no-traces",
			"-D", "no_traces",
			"-D", "ocaml_no_build",
			"-D", "ocaml_output=" + outDir
		];

		final exitCode = Sys.command("haxe", args);
		if (exitCode != 0) throw "haxe compile failed: " + exitCode;

		// `haxe.io.Bytes` should produce alias modules:
		// - Haxe.ml contains `module Io = Haxe_io`
		// - Haxe_io.ml contains `module Bytes = Haxe_io_Bytes`
		final haxeAlias = outDir + "/Haxe.ml";
		if (!sys.FileSystem.exists(haxeAlias)) throw "missing alias module: " + haxeAlias;
		final haxeAliasSrc = sys.io.File.getContent(haxeAlias);
		assertContains(haxeAliasSrc, "module Io = Haxe_io", "Haxe.ml exports Io");

		final haxeIoAlias = outDir + "/Haxe_io.ml";
		if (!sys.FileSystem.exists(haxeIoAlias)) throw "missing alias module: " + haxeIoAlias;
		final haxeIoAliasSrc = sys.io.File.getContent(haxeIoAlias);
		assertContains(haxeIoAliasSrc, "module BytesBuffer = Haxe_io_BytesBuffer", "Haxe_io.ml exports BytesBuffer");
	}
}
