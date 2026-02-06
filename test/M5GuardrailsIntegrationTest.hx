class M5GuardrailsIntegrationTest {
	static function assertOk(args:Array<String>, label:String):Void {
		final p = new sys.io.Process("haxe", args);
		final out = p.stdout.readAll().toString();
		final err = p.stderr.readAll().toString();
		final code = p.exitCode();
		p.close();

		if (code != 0) {
			throw label + ": expected compile to succeed, got exit code " + code + "\n" + out + "\n" + err;
		}
	}

	static function assertFail(args:Array<String>, mustContain:String, label:String):Void {
		final p = new sys.io.Process("haxe", args);
		final out = p.stdout.readAll().toString();
		final err = p.stderr.readAll().toString();
		final code = p.exitCode();
		p.close();

		if (code == 0) throw label + ": expected compile to fail";

		final combined = out + "\n" + err;
		if (combined.indexOf(mustContain) < 0) {
			throw label + ": expected message to contain '" + mustContain + "'";
		}
	}

	static function main() {
		final baseOut = "out_ocaml_m5_guardrails_" + Std.string(Std.int(Date.now().getTime()));
		sys.FileSystem.createDirectory(baseOut);

		final common = [
			"-cp", "test",
			"--no-output",
			"-lib", "reflaxe.ocaml",
			"-D", "no-traces",
			"-D", "no_traces",
			"-D", "ocaml_no_build",
			"-D", "ocaml_no_dune"
		];

		final out1 = baseOut + "/inheritance";
		sys.FileSystem.createDirectory(out1);
		assertOk(common.concat(["-main", "InheritanceMain", "-D", "ocaml_output=" + out1]), "inheritance supported");

		final out2 = baseOut + "/interfaces";
		sys.FileSystem.createDirectory(out2);
		assertOk(common.concat(["-main", "InterfaceMain", "-D", "ocaml_output=" + out2]), "interfaces supported");

		final out3 = baseOut + "/reflection";
		sys.FileSystem.createDirectory(out3);
		assertOk(common.concat(["-main", "ReflectionMain", "-D", "ocaml_output=" + out3]), "reflect field access supported");

			final out4 = baseOut + "/type_reflection";
			sys.FileSystem.createDirectory(out4);
			assertOk(
				common.concat(["-main", "TypeReflectionMain", "-D", "ocaml_output=" + out4]),
				"Type.* reflection supported (minimal)"
			);
		}
	}
