package reflaxe.ocaml.tooling;

/** Argument parsing and beginner-readable output for the `new` command. **/
class ReflaxeOcamlScaffoldCli {
	public static function run(args:Array<String>, packageRoot:String, invocationRoot:String):Int {
		if (args.length == 0 || args[0] == "--help" || args[0] == "-h") {
			Sys.print(help());
			return 0;
		}
		if (args.length < 2) {
			return usageError("new needs a scaffold kind and destination directory.");
		}

		final kind = args[0];
		final destination = args[1];
		var projectName:Null<String> = null;
		var index = 2;
		while (index < args.length) {
			final option = args[index];
			switch (option) {
				case "--name":
					index++;
					if (index >= args.length) {
						return usageError("--name needs a project name.");
					}
					projectName = args[index];
				case "--help", "-h":
					Sys.print(help());
					return 0;
				case _:
					return usageError('Unknown new option: $option');
			}
			index++;
		}

		return switch (ReflaxeOcamlScaffold.create(packageRoot, invocationRoot, kind, destination, projectName)) {
			case Created(summary):
				Sys.println('Created ${summary.kind} project "${summary.projectName}" at:');
				Sys.println('  ${summary.destination}');
				Sys.println("");
				Sys.println("Run these commands from that directory:");
				Sys.println("  haxelib run reflaxe.ocaml doctor --require native");
				if (summary.kind == "app") {
					Sys.println("  haxelib run reflaxe.ocaml build --run .out.reflaxe-ocaml-dune-build/default/out.exe");
					Sys.println("  haxelib run reflaxe.ocaml watch --run .out.reflaxe-ocaml-dune-build/default/out.exe");
				} else {
					Sys.println("  haxelib run reflaxe.ocaml build");
					Sys.println("  haxelib run reflaxe.ocaml watch");
				}
				Sys.println("  haxelib run reflaxe.ocaml inspect --require-lowering");
				Sys.println('REFLAXE_OCAML_SCAFFOLD:PASS kind=${summary.kind} files=${summary.files.length}');
				0;
			case Rejected(message):
				Sys.stderr().writeString(message + "\n");
				Sys.stderr().writeString('REFLAXE_OCAML_SCAFFOLD:FAIL kind=$kind\n');
				2;
		};
	}

	static function usageError(message:String):Int {
		Sys.stderr().writeString(message + "\n\n");
		Sys.stderr().writeString(help());
		return 2;
	}

	public static function help():String {
		return [
			"Create a runnable reflaxe.ocaml starter project",
			"",
			"Usage:",
			"  haxelib run reflaxe.ocaml new app <directory> [--name <project name>]",
			"  haxelib run reflaxe.ocaml new library <directory> [--name <project name>]",
			"",
			"Supported kinds:",
			"  app       Native executable with build, run, and watch commands",
			"  library   Haxe library plus a library-only native Dune build",
			"",
			"The destination must not already exist. Existing files are never overwritten.",
			"Binding, adapter, plugin, and target scaffolds remain unavailable until their typed manifests and shared SDK land.",
			""
		].join("\n");
	}
}
