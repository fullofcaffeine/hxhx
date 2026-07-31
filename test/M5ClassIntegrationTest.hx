class M5ClassIntegrationTest {
	static function assertContains(haystack:String, needle:String, label:String):Void {
		if (haystack.indexOf(needle) < 0) {
			throw label + ": expected to find '" + needle + "'";
		}
	}

	static function assertMatches(haystack:String, re:EReg, label:String):Void {
		if (!re.match(haystack)) {
			throw label + ": expected regex to match";
		}
	}

	static function main() {
		final outDir = "out_ocaml_m5_class_" + Std.string(Std.int(Date.now().getTime()));
		sys.FileSystem.createDirectory(outDir);

		final args = [
			"-cp",
			"test",
			"-main",
			"ClassMain",
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
			"ocaml_no_build"
		];

		final exitCode = Sys.command("haxe", args);
		if (exitCode != 0)
			throw "haxe compile failed: " + exitCode;

		final pointPath = outDir + "/Point.ml";
		if (!sys.FileSystem.exists(pointPath))
			throw "missing output: " + pointPath;
		final pointMl = sys.io.File.getContent(pointPath);
		assertContains(pointMl, "type t = { __hx_type : Obj.t; mutable x : int; mutable y : int }", "record type decl");
		final createRe = ~/let create = fun ([A-Za-z_][A-Za-z0-9_]*) ([A-Za-z_][A-Za-z0-9_]*) ->/;
		if (!createRe.match(pointMl))
			throw "create fn: expected to find 'let create = fun <x> <y> ->'";
		final xArg = createRe.matched(1);
		final yArg = createRe.matched(2);
		// The typed place plan makes receiver-before-RHS order explicit even when both are pure.
		assertMatches(pointMl,
			new EReg("let __place_receiver_[0-9]+ = self in let __place_rhs_[0-9]+ = "
				+ xArg
				+ " in \\(\\s*\\(__place_receiver_[0-9]+ : t\\)\\.x <- __place_rhs_[0-9]+;\\s*__place_rhs_[0-9]+",
				""),
			"ctor assigns x through typed place plan");
		assertMatches(pointMl,
			new EReg("let __place_receiver_[0-9]+ = self in let __place_rhs_[0-9]+ = "
				+ yArg
				+ " in \\(\\s*\\(__place_receiver_[0-9]+ : t\\)\\.y <- __place_rhs_[0-9]+;\\s*__place_rhs_[0-9]+",
				""),
			"ctor assigns y through typed place plan");
		assertContains(pointMl, "incX = fun self () ->", "instance method incX");
		assertMatches(pointMl, ~/let __place_receiver_[0-9]+ = self in let __place_rhs_[0-9]+ = HxInt\.add \(\(self : t\)\.x\) 1 in/,
			"incX plans receiver before rhs");

		final mainPath = outDir + "/ClassMain.ml";
		if (!sys.FileSystem.exists(mainPath))
			throw "missing output: " + mainPath;
		final mainMl = sys.io.File.getContent(mainPath);
		assertContains(mainMl, "Point.create 1 2", "new -> create");
		assertMatches(mainMl, ~/let __call_receiver_[0-9]+ = p in Point\.incX __call_receiver_[0-9]+ \(\)/, "method call (no args)");
		assertMatches(mainMl,
			~/let __call_receiver_[0-9]+ = p in let __call_arg_0_[0-9]+ = 3 in let __call_arg_1_[0-9]+ = 4 in Point\.add __call_receiver_[0-9]+ __call_arg_0_[0-9]+ __call_arg_1_[0-9]+/,
			"method call (args)");
		assertMatches(mainMl, ~/let __call_receiver_[0-9]+ = p in Point\.sum __call_receiver_[0-9]+ \(\)/, "method call returning int");
	}
}
