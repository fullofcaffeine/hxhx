import sys.FileSystem;

/** Executable black-box specification for feature discovery and branch effects in Haxe 4.3.7. */
class M14JsFeatureUpstreamContractTest {
	/** A failed compiler, runtime, or timeout cannot count as a feature observation. */
	static function run(command:String, arguments:Array<String>):String {
		final process = new sys.io.Process(Sys.systemName() == "Mac" ? "gtimeout" : "timeout", ["60", command].concat(arguments));
		final stdout = process.stdout.readAll().toString();
		final stderr = process.stderr.readAll().toString();
		final status = process.exitCode();
		process.close();
		if (status != 0)
			throw "feature observer failed: " + command + ": " + stdout + stderr;
		return stdout;
	}

	/** Separate captures can specialize independently, but one capture cannot change its inferred parameter. */
	static function checkGenericConflict(name:String, mode:String, output:String, diagnostic:String = "Int should be String"):Void {
		final process = new sys.io.Process(Sys.systemName() == "Mac" ? "gtimeout" : "timeout", [
			"60",
			"node_modules/.bin/haxe",
			"-cp",
			"test/fixtures/js_feature_intrinsic",
			"-main",
			name,
			"-dce",
			mode,
			"-js",
			output + "/" + name + "-" + mode + ".js"
		]);
		final stdout = process.stdout.readAll().toString();
		final stderr = process.stderr.readAll().toString();
		final status = process.exitCode();
		process.close();
		if (status != 1 || stderr.indexOf(diagnostic) < 0)
			throw "generic callback conflict did not produce its expected type error: " + stdout + stderr;
		Sys.println("JS_FEATURE_UPSTREAM_GENERIC_CONFLICT:" + name + ":" + mode + ":PASS");
	}

	static function main():Void {
		if (StringTools.trim(run("node_modules/.bin/haxe", ["--version"])) != "4.3.7")
			throw "feature contract requires the pinned Haxe 4.3.7 baseline";
		final output = ".tmp/js_feature_upstream_" + Std.string(Date.now().getTime());
		FileSystem.createDirectory(output);
		M14TraceUpstreamContract.run(output);
		for (mode in ["full", "std", "no"]) {
			check("FeatureBoundOptional", mode, ["1", "first", "2", "second", "1", "third", "true", "7", "false", "9"], output);
			checkGenericConflict("FeatureBoundOptionalMissing", mode, output, "Not enough arguments");
			checkGenericConflict("FeatureBoundOptionalExtra", mode, output, "Too many arguments");
			check("FeatureBoundUnused", mode, ["called", "called", "done"], output);
			check("FeatureBoundNull", mode, ["true", "true", "true", "child", "true", "true", "child"], output);
			checkGenericConflict("FeatureBoundNullConflict", mode, output, "Constraint check failure for select.T");
			check("FeatureBoundCompound", mode, ["compound"], output);
			checkGenericConflict("FeatureBoundCompoundMissingInterface", mode, output, "Constraint check failure for echo.T");
			checkGenericConflict("FeatureBoundCompoundMissingBase", mode, output, "Constraint check failure for echo.T");
			check("FeatureBoundInterface", mode, ["interface"], output);
			checkGenericConflict("FeatureBoundInterfaceConflict", mode, output, "Int should be String");
			checkGenericConflict("FeatureBoundInterfaceUndeclared", mode, output, "Constraint check failure for echo.T");
			check("FeatureBoundApplied", mode, ["child", "child"], output);
			checkGenericConflict("FeatureBoundAppliedConflict", mode, output, "Constraint check failure for echo.U");
			check("FeatureBoundConstraint", mode, ["child", "child"], output);
			check("FeatureBoundConstraintCapture", mode, ["7"], output);
			checkGenericConflict("FeatureBoundConstraintDirect", mode, output, "Constraint check failure for echo.T");
			checkGenericConflict("foreign.FeatureBoundConstraintForeign", mode, output, "Constraint check failure for echo.T");
			check("FeatureBoundSubtype", mode, ["child"], output);
			check("FeatureBoundExpected", mode, ["written", "argument", "class", "9"], output);
			checkGenericConflict("FeatureBoundMethodGenericConflict", mode, output);
			checkGenericConflict("FeatureBoundMethodGenericAliasConflict", mode, output);
			check("FeatureBoundMethodGeneric", mode, ["text", "7", "direct", "wrapped"], output);
			check("FeatureBoundGeneric", mode, ["text", "7", "inherited", "implicit"], output);
			check("FeatureBoundInheritance", mode, ["child:initial", "child:initial", "true", "child:changed", "child:changed"], output);
			check("FeatureBoundContexts", mode, [
				"static",
				"instance",
				"constructor",
				"local",
				"local",
				"shadow",
				"old:changed",
				"replacement",
				"false",
				"true"
			], output);
			check("FeatureDynamic", mode, ["original:on", "replacement:on", "replacement:called"], output);
			check("FeatureBoundMethod", mode, [
				"bound:on",
				"make:first",
				"make:second",
				"first",
				"second",
				"changed",
				"true",
				"false",
				"make:temporary",
				"temporary"
			], output);
			check("FeatureStartup", mode, [
				"later:init",
				"entry:init",
				"later:method",
				"later:field",
				"entry:field",
				"3",
				"4"
			], output);
			check("FeatureEmission", mode, (mode == "full" ? [] : ["primary:effect", "unused:effect"]).concat(["conditional:effect", "absent", "3"]), output);
			check("FeatureMetadata", mode, (mode == "full" ? [] : ["field:effect"]).concat([
				mode == "full" ? "effect:off" : "effect:on",
				"init:on",
				mode == "full" ? "init-method:off" : "init-method:on",
				"sub:on",
				"base:on",
				"exposed:on",
				"private:on",
				"init-class:on"
			]), output);
			check("FeatureDispatch", mode, [
				"parent:on",
				"child:on",
				"class-only:on",
				mode == "full" ? "unused:off" : "unused:on",
				"interface:on",
				mode == "full" ? "unrelated:off" : "unrelated:on",
				"follow:on",
				"child:called",
				"interface:called",
				"true",
				"true"
			], output);
			check("FeatureClassValues", mode, [
				"child:on",
				"parent:on",
				"interface:on",
				"child-init:on",
				"parent-init:on",
				mode == "full" ? "unused:off" : "unused:on",
				"true"
			], output);
			check("FeatureReferences", mode, ["hidden:on", "leaf:on", "callback:on", "true"], output);
			check("FeatureRetention", mode, [
				"init:on",
				"kept:on",
				mode == "full" ? "field:off" : "field:on",
				mode == "full" ? "unused:off" : "unused:on",
				"kept-class:on",
				mode == "full" ? "unused-class:off" : "unused-class:on",
				mode == "full" ? "unused-init:off" : "unused-init:on"
			], output);
			check("Main", mode, ["enabled", "branch", "absent"], output);
			check("FeatureFields", mode, ["field:effect", "selected"], output);
			check("FeatureNames", mode, ["module:off", "short:on", "module-class:off", "short-class:on", "touch"], output);
			check("FeatureShadowing", mode, ["local:probe.shadow:yes:no", "method:probe.method:value"], output);
			check("FeatureContract", mode, [
				"late:on",
				"define:effect",
				"absent:off",
				mode == "full" ? "unused:off" : "unused:on",
				"method:on",
				"class:on",
				"value:effect",
				"selected",
				"definition-value",
				"value:on",
				"active:called"
			], output);
			check("FeatureReachability", mode, [
				"nested:on",
				"fallback:on",
				"fallback:effect",
				"cycle:b",
				"cycle:a",
				"cycle:on",
				"conditional:on",
				"missing:off"
			], output);
		}
		FileSystem.deleteDirectory(output);
		Sys.println("JS_FEATURE_UPSTREAM_CONTRACT:PASS");
	}

	/** Ignore only the compiler's trace location prefix; retain every effect and its exact order. */
	static function check(module:String, mode:String, expected:Array<String>, output:String):Void {
		final script = output + "/" + module + "-" + mode + ".js";
		run("node_modules/.bin/haxe", [
			"-cp",
			"test/fixtures/js_feature_intrinsic",
			"-main",
			module,
			"-js",
			script,
			"-dce",
			mode
		]);
		final stdout = run("node", [script]);
		final prefix = ~/^test\/fixtures\/js_feature_intrinsic\/[A-Za-z]+\.hx:[0-9]+: /;
		final actual = [for (line in StringTools.trim(stdout).split("\n")) prefix.replace(line, "")];
		if (actual.join("\n") != expected.join("\n"))
			throw "upstream feature contract differs: " + module + ": " + mode + "\n" + stdout;
		FileSystem.deleteFile(script);
		Sys.println("JS_FEATURE_UPSTREAM:" + module + ":" + mode + ":PASS");
	}
}
