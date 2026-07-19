package reflaxe.ocaml.tooling;

import haxe.Json;
import haxe.io.Path;
import sys.FileSystem;
import sys.io.File;

/**
	User-facing command dispatcher for reflaxe.ocaml authoring tools.

	Commands return exit codes instead of terminating directly so focused tests
	and future editor integrations can reuse the same behavior.
**/
class ReflaxeOcamlCli {
	public static function run(rawArgs:Array<String>, packageRoot:String, invocationRoot:String):Int {
		final args = rawArgs.copy();
		if (args.length == 0) {
			Sys.print(help());
			return 0;
		}

		final command = args.shift();
		return switch (command) {
			case "doctor": runDoctor(args, packageRoot, invocationRoot);
			case "version", "--version", "-v":
				Sys.println('reflaxe.ocaml ${readPackageVersion(packageRoot)}');
				0;
			case "help", "--help", "-h":
				Sys.print(help());
				0;
			case _:
				Sys.stderr().writeString('Unknown reflaxe.ocaml command: $command\n\n');
				Sys.stderr().writeString(help());
				2;
		};
	}

	static function runDoctor(args:Array<String>, packageRoot:String, invocationRoot:String):Int {
		var json = false;
		var requiredCapability = "source";
		var projectRoot = invocationRoot;
		var index = 0;
		while (index < args.length) {
			final option = args[index];
			switch (option) {
				case "--json":
					json = true;
				case "--require":
					index++;
					if (index >= args.length) {
						return usageError("--require needs source, native, compiler, or hxhx.");
					}
					requiredCapability = args[index];
				case "--project":
					index++;
					if (index >= args.length) {
						return usageError("--project needs a directory path.");
					}
					projectRoot = FileSystem.absolutePath(args[index]);
				case "--help", "-h":
					Sys.print(doctorHelp());
					return 0;
				case _:
					return usageError('Unknown doctor option: $option');
			}
			index++;
		}

		if (!ReflaxeOcamlDoctor.REQUIRED_CAPABILITIES.contains(requiredCapability)) {
			return usageError('Unknown required capability: $requiredCapability');
		}
		if (!FileSystem.exists(projectRoot) || !FileSystem.isDirectory(projectRoot)) {
			return usageError('Project directory does not exist: $projectRoot');
		}

		final report = ReflaxeOcamlDoctor.inspect(new SystemDoctorProbe(), packageRoot, projectRoot, readPackageVersion(packageRoot), requiredCapability);
		Sys.print(json ? ReflaxeOcamlDoctor.renderJson(report) : ReflaxeOcamlDoctor.renderHuman(report));
		return report.summary.exitCode;
	}

	static function readPackageVersion(packageRoot:String):String {
		final candidates = [
			Path.join([packageRoot, "haxelib.json"]),
			Path.join([packageRoot, "packages", "reflaxe.ocaml", "haxelib.json"])
		];
		for (candidate in candidates) {
			if (!FileSystem.exists(candidate)) {
				continue;
			}
			try {
				final data:Dynamic = Json.parse(File.getContent(candidate));
				if (Reflect.field(data, "name") == "reflaxe.ocaml") {
					final version:Null<String> = Reflect.field(data, "version");
					if (version != null && version.length > 0) {
						return version;
					}
				}
			} catch (_:Dynamic) {}
		}
		return "unknown";
	}

	static function usageError(message:String):Int {
		Sys.stderr().writeString(message + "\n\n");
		Sys.stderr().writeString(doctorHelp());
		return 2;
	}

	static function help():String {
		return [
			"reflaxe.ocaml - Haxe to OCaml authoring tools",
			"",
			"Usage:",
			"  haxelib run reflaxe.ocaml <command> [options]",
			"",
			"Commands:",
			"  doctor    Diagnose source, native, compiler-authoring, and hxhx readiness",
			"  version   Print the reflaxe.ocaml package version",
			"  help      Show this help",
			"",
			"Run `haxelib run reflaxe.ocaml doctor --help` for doctor options.",
			""
		].join("\n");
	}

	static function doctorHelp():String {
		return [
			"Diagnose the reflaxe.ocaml development environment",
			"",
			"Usage:",
			"  haxelib run reflaxe.ocaml doctor [options]",
			"",
			"Options:",
			"  --json                         Print the stable machine-readable report",
			"  --project <directory>          Inspect project lock files in this directory",
			"  --require <capability>         Gate source (default), native, compiler, or hxhx",
			"  --help                         Show this help",
			"",
			"Examples:",
			"  haxelib run reflaxe.ocaml doctor",
			"  haxelib run reflaxe.ocaml doctor --require native",
			"  haxelib run reflaxe.ocaml doctor --json --require compiler",
			""
		].join("\n");
	}
}
