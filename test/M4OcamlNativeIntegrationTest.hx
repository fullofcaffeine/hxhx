class M4OcamlNativeIntegrationTest {
	static function assertContains(haystack:String, needle:String, label:String):Void {
		if (haystack.indexOf(needle) < 0) {
			throw label + ": expected to find '" + needle + "'";
		}
	}

	static function assertNotContains(haystack:String, needle:String, label:String):Void {
		if (haystack.indexOf(needle) >= 0) {
			throw label + ": expected to NOT find '" + needle + "'";
		}
	}

	static function main() {
		final outDir = "out_ocaml_m4_ocaml_native_" + Std.string(Std.int(Date.now().getTime()));
		sys.FileSystem.createDirectory(outDir);

		final args = [
			"-cp",
			"test",
			"-main",
			"OcamlNativeMain",
			"--no-output",
			"-lib",
			"reflaxe.ocaml",
			"-D",
			"no-traces",
			"-D",
			"no_traces",
			"-D",
			"ocaml_output=" + outDir
		];

		final exitCode = Sys.command("haxe", args);
		if (exitCode != 0)
			throw "haxe compile failed: " + exitCode;

		// Ensure we didn't emit duplicate ocaml.* type declarations.
		if (sys.FileSystem.exists(outDir + "/ocaml_List.ml"))
			throw "unexpected ocaml_List.ml emission";
		if (sys.FileSystem.exists(outDir + "/ocaml_Option.ml"))
			throw "unexpected ocaml_Option.ml emission";
		if (sys.FileSystem.exists(outDir + "/ocaml_Result.ml"))
			throw "unexpected ocaml_Result.ml emission";
		if (sys.FileSystem.exists(outDir + "/ocaml_Ref.ml"))
			throw "unexpected ocaml_Ref.ml emission";

		final mainPath = outDir + "/OcamlNativeMain.ml";
		if (!sys.FileSystem.exists(mainPath))
			throw "missing output: " + mainPath;
		final ml = sys.io.File.getContent(mainPath);

		// Lists: `Nil`/`Cons` -> `[]` / `::`
		assertContains(ml, "1 :: 2 :: []", "list construction");
		assertContains(ml, "| [] ->", "list nil pattern");
		assertContains(ml, "::", "list cons pattern");
		assertNotContains(ml, "Ocaml_List.", "no module-qualified list constructors");

		// Options: `None`/`Some`
		assertContains(ml, "Some 1", "option construction");
		assertContains(ml, "| None ->", "option none pattern");
		assertContains(ml, "| Some", "option some pattern");
		assertNotContains(ml, "Ocaml_Option.", "no module-qualified option constructors");

		// Results: `Ok`/`Error`
		assertContains(ml, "Ok 1", "result construction");
		assertContains(ml, "| Ok", "result ok pattern");
		assertContains(ml, "| Error", "result error pattern");
		assertNotContains(ml, "Ocaml_Result.", "no module-qualified result constructors");

		// Refs: `Ref.make/get/set` -> `ref` / `!` / `:=`
		assertContains(ml, "let rr = ref 1", "ref creation");
		assertContains(ml, "!rr", "ref deref");
		assertContains(ml, "rr := ", "ref assignment");
		assertNotContains(ml, "Ocaml_Ref.", "no module-qualified ref calls");
	}
}
