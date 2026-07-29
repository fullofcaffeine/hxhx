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
			case "new": ReflaxeOcamlScaffoldCli.run(args, packageRoot, invocationRoot);
			case "build": runAuthoring(args, invocationRoot, false);
			case "watch": runAuthoring(args, invocationRoot, true);
			case "inspect": runInspection(args, invocationRoot);
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

	static function runInspection(args:Array<String>, invocationRoot:String):Int {
		var projectRoot = invocationRoot;
		var outputPath = "out";
		var json = false;
		var requireLowering = false;
		var index = 0;
		while (index < args.length) {
			final option = args[index];
			switch (option) {
				case "--project":
					index++;
					if (index >= args.length) {
						return inspectionUsageError("--project needs a directory path.");
					}
					projectRoot = resolveFrom(invocationRoot, args[index]);
				case "--output":
					index++;
					if (index >= args.length) {
						return inspectionUsageError("--output needs a project-relative directory path.");
					}
					outputPath = args[index];
				case "--json":
					json = true;
				case "--require-lowering":
					requireLowering = true;
				case "--help", "-h":
					Sys.print(inspectionHelp());
					return 0;
				case _:
					return inspectionUsageError('Unknown inspect option: $option');
			}
			index++;
		}
		if (!FileSystem.exists(projectRoot) || !FileSystem.isDirectory(projectRoot)) {
			return inspectionUsageError('Project directory does not exist: $projectRoot');
		}
		final outputDirectory = resolveFrom(projectRoot, outputPath);
		final report = ReflaxeOcamlInspection.inspect(projectRoot, outputDirectory, requireLowering);
		Sys.print(json ? ReflaxeOcamlInspection.renderJson(report) : ReflaxeOcamlInspection.renderHuman(report));
		return report.summary.exitCode;
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
					projectRoot = resolveFrom(invocationRoot, args[index]);
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

	static function runAuthoring(args:Array<String>, invocationRoot:String, watchCommand:Bool):Int {
		var projectRoot = invocationRoot;
		var hxmlPath = "build.hxml";
		var outputPath = "out";
		var watch = watchCommand;
		final watchPaths = new Array<String>();
		var pollMilliseconds = 250;
		var debounceMilliseconds = 100;
		var maxBuilds:Null<Int> = null;
		var runArtifact:Null<String> = null;
		final runArguments = new Array<String>();
		var index = 0;
		while (index < args.length) {
			final option = args[index];
			switch (option) {
				case "--project":
					index++;
					if (index >= args.length) {
						return authoringUsageError("--project needs a directory path.", watchCommand);
					}
					projectRoot = resolveFrom(invocationRoot, args[index]);
				case "--hxml":
					index++;
					if (index >= args.length) {
						return authoringUsageError("--hxml needs a project-relative file path.", watchCommand);
					}
					hxmlPath = args[index];
				case "--output":
					index++;
					if (index >= args.length) {
						return authoringUsageError("--output needs a project-relative directory path.", watchCommand);
					}
					outputPath = args[index];
				case "--watch":
					watch = true;
				case "--watch-path":
					index++;
					if (index >= args.length) {
						return authoringUsageError("--watch-path needs a file or directory.", watchCommand);
					}
					watchPaths.push(args[index]);
				case "--poll-ms":
					index++;
					if (index >= args.length) {
						return authoringUsageError("--poll-ms needs a positive integer.", watchCommand);
					}
					final parsed = positiveInteger(args[index]);
					if (parsed == null) {
						return authoringUsageError("--poll-ms needs a positive integer.", watchCommand);
					}
					pollMilliseconds = parsed;
				case "--debounce-ms":
					index++;
					if (index >= args.length) {
						return authoringUsageError("--debounce-ms needs a positive integer.", watchCommand);
					}
					final parsed = positiveInteger(args[index]);
					if (parsed == null) {
						return authoringUsageError("--debounce-ms needs a positive integer.", watchCommand);
					}
					debounceMilliseconds = parsed;
				case "--max-builds":
					index++;
					if (index >= args.length) {
						return authoringUsageError("--max-builds needs a positive integer.", watchCommand);
					}
					maxBuilds = positiveInteger(args[index]);
					if (maxBuilds == null) {
						return authoringUsageError("--max-builds needs a positive integer.", watchCommand);
					}
				case "--run":
					index++;
					if (index >= args.length) {
						return authoringUsageError("--run needs an executable path.", watchCommand);
					}
					runArtifact = args[index];
				case "--run-arg":
					index++;
					if (index >= args.length) {
						return authoringUsageError("--run-arg needs one argument value.", watchCommand);
					}
					runArguments.push(args[index]);
				case "--help", "-h":
					Sys.print(authoringHelp(watchCommand));
					return 0;
				case _:
					return authoringUsageError('Unknown ${watchCommand ? "watch" : "build"} option: $option', watchCommand);
			}
			index++;
		}

		if (!watch && maxBuilds != null) {
			return authoringUsageError("--max-builds is only meaningful with watch or build --watch.", watchCommand);
		}
		if (runArtifact == null && runArguments.length > 0) {
			return authoringUsageError("--run-arg requires --run <executable>.", watchCommand);
		}

		final options:AuthoringBuildOptions = {
			hxmlPath: hxmlPath,
			outputPath: outputPath,
			watch: watch,
			watchPaths: watchPaths,
			pollMilliseconds: pollMilliseconds,
			debounceMilliseconds: debounceMilliseconds,
			maxBuilds: maxBuilds,
			runArtifact: runArtifact,
			runArguments: runArguments
		};
		return ReflaxeOcamlAuthoring.run(new SystemAuthoringHost(), projectRoot, options);
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

	static function authoringUsageError(message:String, watchCommand:Bool):Int {
		Sys.stderr().writeString(message + "\n\n");
		Sys.stderr().writeString(authoringHelp(watchCommand));
		return 2;
	}

	static function inspectionUsageError(message:String):Int {
		Sys.stderr().writeString(message + "\n\n");
		Sys.stderr().writeString(inspectionHelp());
		return 2;
	}

	static function positiveInteger(value:String):Null<Int> {
		if (!~/^[1-9][0-9]*$/.match(value)) {
			return null;
		}
		final parsed = Std.parseInt(value);
		return parsed != null ? parsed : null;
	}

	static function resolveFrom(base:String, path:String):String {
		return FileSystem.absolutePath(Path.isAbsolute(path) ? path : Path.join([base, path]));
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
			"  new       Create a runnable application or library starter project",
			"  build     Run one fresh Haxe-to-OCaml project build, optionally followed by an executable",
			"  watch     Rebuild after stable source changes without reusing a Haxe server",
			"  inspect   Explain the compiler-owned artifacts from one completed build",
			"  version   Print the reflaxe.ocaml package version",
			"  help      Show this help",
			"",
			"Run a command with --help for its options.",
			""
		].join("\n");
	}

	static function inspectionHelp():String {
		return [
			"Inspect a completed reflaxe.ocaml build",
			"",
			"Usage:",
			"  haxelib run reflaxe.ocaml inspect [options]",
			"",
			"Options:",
			"  --project <directory>          Project working directory (default: current project)",
			"  --output <directory>           OCaml output; relative paths use the project (default: out)",
			"  --json                         Print the stable machine-readable report",
			"  --require-lowering             Fail unless typed place-lowering data is present",
			"  --help                         Show this help",
			"",
			"Run a successful build before inspection. Add -D ocaml_lowering_report to the HXML",
			"to inspect the migrated typed-lowering families. Native timing appears when",
			"the build used -D ocaml_build_timing_report (build/watch request it automatically).",
			""
		].join("\n");
	}

	static function authoringHelp(watchCommand:Bool):String {
		final command = watchCommand ? "watch" : "build";
		return [
			'${watchCommand ? "Watch and rebuild" : "Build"} a reflaxe.ocaml project',
			"",
			"Usage:",
			'  haxelib run reflaxe.ocaml $command [options]',
			"",
			"Options:",
			"  --project <directory>          Project working directory (default: current project)",
			"  --hxml <file>                  HXML to run (default: build.hxml)",
			"  --output <directory>           OCaml output used for native timing (default: out)",
			"  --watch                        Keep rebuilding after edits (build command only)",
			"  --watch-path <path>            Add an input file/directory; repeat as needed",
			"  --poll-ms <milliseconds>       Poll interval (default: 250)",
			"  --debounce-ms <milliseconds>   Required stable interval (default: 100)",
			"  --max-builds <count>           Stop after this many attempts (watch/testing)",
			"  --run <executable>             Run this project-relative artifact after each success",
			"  --run-arg <value>              Add one artifact argument; repeat as needed",
			"  --help                         Show this help",
			"",
			"Examples:",
			"  haxelib run reflaxe.ocaml build",
			"  haxelib run reflaxe.ocaml build --run .out.reflaxe-ocaml-dune-build/default/out.exe",
			"  haxelib run reflaxe.ocaml watch --run .out.reflaxe-ocaml-dune-build/default/out.exe",
			"",
			"The command atomically publishes generated source before Dune runs. Dune keeps reusable",
			"state in .<output>.reflaxe-ocaml-dune-build beside the output directory. Timing keeps",
			"typecheck, compile, and link combined; cache hits, startup, and runtime are not inferred.",
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
