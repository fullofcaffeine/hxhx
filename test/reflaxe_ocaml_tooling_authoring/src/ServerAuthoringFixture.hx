import reflaxe.ocaml.tooling.ReflaxeOcamlCli;

/**
	Invokes the public authoring CLI with a real external Haxe server.

	The surrounding shell owns the server and supplies paths through the
	environment so the Lix Haxe shim does not mistake the CLI's nested
	`--connect` argument for an option to the outer interpreter process.
**/
class ServerAuthoringFixture {
	static function main():Void {
		final project = requiredEnvironment("REFLAXE_OCAML_SERVER_PROJECT");
		final endpoint = requiredEnvironment("REFLAXE_OCAML_SERVER_ENDPOINT");
		final root = Sys.getCwd();
		final exitCode = ReflaxeOcamlCli.run([
			"build",
			"--project",
			project,
			"--connect",
			endpoint,
			"--run",
			".out.reflaxe-ocaml-dune-build/default/out.exe"
		], root, root);
		Sys.exit(exitCode);
	}

	static function requiredEnvironment(name:String):String {
		final value = Sys.getEnv(name);
		if (value == null || value.length == 0) {
			throw 'Missing $name';
		}
		return value;
	}
}
