class M8ModuleCollisionIntegrationTest {
	static function assertFail(args:Array<String>, mustContain:Array<String>, label:String):Void {
		final p = new sys.io.Process("haxe", args);
		final out = p.stdout.readAll().toString();
		final err = p.stderr.readAll().toString();
		final code = p.exitCode();
		p.close();

		if (code == 0) throw label + ": expected compile to fail";

		final combined = out + "\n" + err;
		for (s in mustContain) {
			if (combined.indexOf(s) < 0) {
				throw label + ": expected message to contain '" + s + "'";
			}
		}
	}

	static function main() {
		final outDir = "out_ocaml_m8_collisions_" + Std.string(Std.int(Date.now().getTime()));
		sys.FileSystem.createDirectory(outDir);

		final args = [
			"-cp", "test/collision",
			"-main", "Main",
			"--no-output",
			"-lib", "reflaxe.ocaml",
			"-D", "no-traces",
			"-D", "no_traces",
			"-D", "ocaml_no_build",
			"-D", "ocaml_no_dune",
			"-D", "ocaml_output=" + outDir
		];

		assertFail(
			args,
			[
				"module filename collision",
				"a.b.C",
				"a_b.C",
				"haxe.ocaml-28t.9.7"
			],
			"module filename collision detector"
		);
	}
}

