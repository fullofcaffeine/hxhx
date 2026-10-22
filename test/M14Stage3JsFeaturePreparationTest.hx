import haxe.io.Path;
import sys.io.File;

/** Exercise feature selection through the compiler driver, before any JS projection. */
class M14Stage3JsFeaturePreparationTest {
	/** Both compiler and Node failures remain failures of the observable contract. */
	static function run(command:String, arguments:Array<String>):String {
		final process = new sys.io.Process(Sys.systemName() == "Mac" ? "gtimeout" : "timeout", ["60", command].concat(arguments));
		final stdout = process.stdout.readAll().toString();
		final stderr = process.stderr.readAll().toString();
		final exit = process.exitCode();
		process.close();
		if (exit != 0)
			throw "feature observer failed: " + command + ": " + stdout + stderr;
		return stdout;
	}

	/** Compare a resolved driver request with fixed stdout and upstream behavior; providers share that same contract. */
	static function check(input:{
		output:String,
		entry:String,
		mode:String,
		providers:Array<Bool>
	}):Void {
		final library = input.entry.length == 0;
		final suffix = input.mode + "-" + (library ? "library" : input.entry);
		final source = library ? ["FeatureRetention"] : ["-main", input.entry];
		final dce = input.mode == "default" ? [] : ["-dce", input.mode];
		final upstream = input.output + "/upstream-" + suffix + ".js";
		final common = ["-cp", "test/fixtures/js_feature_intrinsic"].concat(source).concat(dce);
		run("node_modules/.bin/haxe", common.concat(["-js", upstream]));
		final expected = library ? "" : input.entry == "Main" ? "enabled\nbranch\nabsent\n" : input.entry == "featureentry.Main" ? "packaged:on\n" : "JS_ORACLE|arr-comp:4:1:7\n";
		// Upstream trace prefixes are presentation; the independently authored values are fixed.
		final upstreamValues = [
			for (line in run("node", [upstream]).split("\n"))
				if (line.length > 0) line.substr(line.indexOf(": ") + 2)
		];
		if ((upstreamValues.length == 0 ? "" : upstreamValues.join("\n") + "\n") != expected)
			throw "upstream branch contract changed";
		for (promoted in input.providers) {
			final script = input.output + "/native-" + suffix + "-" + promoted + ".js";
			final provider = promoted ? ["-D", "hxhx_backend_provider=Stage3JsFeaturePreparationProvider"] : [];
			final before = Stage3JsFeaturePreparationProvider.requests;
			final status = hxhx.Stage3Compiler.run(["--hxhx-backend", "js-native", "--hxhx-no-run"].concat(common).concat(provider).concat(["-js", script]));
			if (status != 0 || run("node", [script]) != expected)
				throw "normal JS entrypoint differs: " + suffix + ": " + status;
			if ((Stage3JsFeaturePreparationProvider.requests > before) != promoted)
				throw "driver did not select the requested provider route";
		}
	}

	static function main():Void {
		if (StringTools.trim(run("node_modules/.bin/haxe", ["--version"])) != "4.3.7")
			throw "feature contract requires Haxe 4.3.7";
		final output = Path.normalize(Sys.getCwd() + "/.tmp/stage3_js_features_" + Date.now().getTime());
		sys.FileSystem.createDirectory(output);
		for (mode in ["default", "full", "std", "no"])
			for (entry in ["Main", "featureentry.Main", ""])
				check({
					output: output,
					entry: entry,
					mode: mode,
					providers: [false, true]
				});
		// The original expensive oracle case is one complete default-mode tracer, not a repeated DCE matrix.
		check({
			output: output,
			entry: "JsOracleArrayComprehensionMain",
			mode: "default",
			providers: [false]
		});
		// The retention fixture distinguishes std from full: omitted mode must match std byte for byte.
		for (mode in ["default", "std"]) {
			final arguments = ["-cp", "test/fixtures/js_feature_intrinsic", "-main", "FeatureRetention"];
			if (mode == "std")
				arguments.push("-dce");
			if (mode == "std")
				arguments.push("std");
			run("node_modules/.bin/haxe", arguments.concat(["-js", output + "/retention-" + mode + ".js"]));
		}
		if (File.getContent(output + "/retention-default.js") != File.getContent(output + "/retention-std.js"))
			throw "omitted upstream DCE no longer matches std";
		Sys.println("STAGE3_JS_FEATURE_PREPARATION:PASS");
	}
}

/** Load the existing promoted JS backend through the normal request provider mechanism. */
class Stage3JsFeaturePreparationProvider implements backend.ITargetBackendProvider {
	public static var requests:Int = 0;

	public function new() {}

	public function registrations():Array<backend.BackendRegistrationSpec> {
		requests++;
		return backend.js.JsBackend.providerRegistrations();
	}
}
