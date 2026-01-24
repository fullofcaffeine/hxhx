class M4EnumIntegrationTest {
	static function assertContains(haystack:String, needle:String, label:String):Void {
		if (haystack.indexOf(needle) < 0) {
			throw label + ": expected to find '" + needle + "'";
		}
	}

	static function main() {
		final outDir = "out_ocaml_m4_enum_" + Std.string(Std.int(Date.now().getTime()));
		sys.FileSystem.createDirectory(outDir);

		final args = [
			"-cp", "test",
			"-main", "EnumMain",
			"--no-output",
			"-lib", "reflaxe.ocaml",
			"-D", "no-traces",
			"-D", "no_traces",
			"-D", "ocaml_output=" + outDir
		];

		final exitCode = Sys.command("haxe", args);
		if (exitCode != 0) throw "haxe compile failed: " + exitCode;

		final enumPath = outDir + "/MyEnum.ml";
		if (!sys.FileSystem.exists(enumPath)) throw "missing output: " + enumPath;
		final enumMl = sys.io.File.getContent(enumPath);
		assertContains(enumMl, "type myenum", "enum type decl");
		assertContains(enumMl, "| A", "ctor A");
		assertContains(enumMl, "| B of int", "ctor B");
		assertContains(enumMl, "| C of int * string", "ctor C");

		final mainPath = outDir + "/EnumMain.ml";
		if (!sys.FileSystem.exists(mainPath)) throw "missing output: " + mainPath;
		final mainMl = sys.io.File.getContent(mainPath);
		assertContains(mainMl, "MyEnum.C (1, \"x\")", "multi-arg ctor call uses tuple");
		assertContains(mainMl, "match", "switch->match");
		assertContains(mainMl, "| MyEnum.A ->", "ctor pattern A");
		assertContains(mainMl, "| MyEnum.B", "ctor pattern B");
		assertContains(mainMl, "| MyEnum.C", "ctor pattern C");
	}
}

