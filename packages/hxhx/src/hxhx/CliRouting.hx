package hxhx;

import hxhx.Stage1Compiler.Stage1Args;

typedef CliRoutePlan = {
	final lane:String;
	final backendId:Null<String>;
	final forwarded:Array<String>;
	final stage0Required:Bool;
}

private typedef StandardTargetScan = {
	final hasJs:Bool;
	final hasNonJs:Bool;
	final hasLegacy:Bool;
	final missingValueFlag:Null<String>;
}

class CliRouting {
	public static inline final LANE_NATIVE_OCAML:String = "native-ocaml";
	public static inline final LANE_NATIVE_JS:String = "native-js";
	public static inline final LANE_STAGE0_COMPAT:String = "stage0-compat";
	public static inline final LANE_STAGE0_OCAML_EVAL:String = "stage0-ocaml-eval";

	public static function listLaneSelectors():Array<String> {
		return ["ocaml", "ocaml-eval", "js", "compat"];
	}

	public static function plan(shimArgs:Array<String>, forwarded:Array<String>):CliRoutePlan {
		if (hasFlag(shimArgs, "--target") || hasFlag(shimArgs, "--hxhx-target")) {
			throw "--target removed; use --ocaml, --ocaml-eval, Haxe --js <file>, or --compat";
		}

		final compatRequested = hasFlag(shimArgs, "--compat");
		final ocamlRequested = hasFlag(shimArgs, "--ocaml");
		final ocamlEvalRequested = hasFlag(shimArgs, "--ocaml-eval");

		if (compatRequested && (ocamlRequested || ocamlEvalRequested)) {
			throw "Use --ocaml (native) or --ocaml-eval (delegated). --compat is pure upstream passthrough.";
		}

		final baseForwarded = stripRoutingFlags(forwarded);
		final targetScan = scanStandardTargetFlags(planningTargetArgs(baseForwarded));

		if (targetScan.missingValueFlag != null && (targetScan.missingValueFlag == "--js" || targetScan.missingValueFlag == "-js")) {
			throw "Missing value after --js/ -js";
		}

		if (compatRequested) {
			return {
				lane: LANE_STAGE0_COMPAT,
				backendId: null,
				forwarded: baseForwarded,
				stage0Required: true
			};
		}

		if (ocamlEvalRequested) {
			if (targetScan.hasJs || targetScan.hasNonJs) {
				throw "--ocaml-eval is the target; remove other targets.";
			}
			final evalArgs = baseForwarded.copy();
			final evalReflaxeTarget = getDefineValue(evalArgs, "reflaxe-target");
			if (evalReflaxeTarget != null && evalReflaxeTarget != "ocaml") {
				throw "Contradiction: --ocaml-eval but -D reflaxe-target=" + evalReflaxeTarget;
			}
			addLibraryIfMissing(evalArgs, "reflaxe.ocaml");
			addMacroIfMissing(evalArgs, "reflaxe.ReflectCompiler.InitMacro.init()");
			addMacroIfMissing(evalArgs, "reflaxe.ReflectCompiler.ReflectCompiler_Addon.addon()");
			addDefineIfMissing(evalArgs, "reflaxe-target=ocaml");
			addDefineIfMissing(evalArgs, "target.name=ocaml");
			addDefineIfMissing(evalArgs, "ocaml_output=out");
			addDefineIfMissing(evalArgs, "ocaml_build=1");
			addDefineIfMissing(evalArgs, "ocaml_bin=main");
			if (evalArgs.indexOf("--no-output") == -1)
				evalArgs.push("--no-output");
			return {
				lane: LANE_STAGE0_OCAML_EVAL,
				backendId: null,
				forwarded: evalArgs,
				stage0Required: true
			};
		}

		if (ocamlRequested) {
			if (targetScan.hasJs || targetScan.hasNonJs) {
				throw "--ocaml is the target; remove other targets.";
			}
			final nativeOcaml = baseForwarded.copy();
			final nativeReflaxeTarget = getDefineValue(nativeOcaml, "reflaxe-target");
			if (nativeReflaxeTarget != null && nativeReflaxeTarget != "ocaml") {
				throw "Contradiction: --ocaml but -D reflaxe-target=" + nativeReflaxeTarget;
			}
			final defineOut = getDefineValue(nativeOcaml, "ocaml_output");
			final hxhxOut = findFlagValue(nativeOcaml, "--hxhx-out");
			final outDir = defineOut != null
				&& defineOut.length > 0 ? defineOut : (hxhxOut != null && hxhxOut.length > 0 ? hxhxOut : "out");

			if (defineOut != null && defineOut.length > 0 && hxhxOut != null && hxhxOut.length > 0 && defineOut != hxhxOut) {
				throw "conflicting output directories: -D ocaml_output=" + defineOut + " and --hxhx-out " + hxhxOut;
			}
			if (hxhxOut == null || hxhxOut.length == 0) {
				nativeOcaml.push("--hxhx-out");
				nativeOcaml.push(outDir);
			}

			addDefineIfMissing(nativeOcaml, "ocaml_output=" + outDir);
			addDefineIfMissing(nativeOcaml, "reflaxe-target=ocaml");
			addDefineIfMissing(nativeOcaml, "target.name=ocaml");

			return {
				lane: LANE_NATIVE_OCAML,
				backendId: "ocaml-stage3",
				forwarded: nativeOcaml,
				stage0Required: false
			};
		}

		if (targetScan.hasJs && !targetScan.hasNonJs) {
			final nativeJs = baseForwarded.copy();
			addDefineIfMissing(nativeJs, "js");
			addDefineIfMissing(nativeJs, "target.name=js");
			return {
				lane: LANE_NATIVE_JS,
				backendId: "js-native",
				forwarded: nativeJs,
				stage0Required: false
			};
		}

		if (targetScan.hasLegacy) {
			final legacy = findUnsupportedLegacyTarget(baseForwarded);
			if (legacy != null) {
				throw 'Target "' + legacy + '" is not supported in this implementation. Legacy Flash/AS3 targets are intentionally unsupported.';
			}
		}

		if (targetScan.hasNonJs) {
			throw "Target not supported natively; rerun with --compat.";
		}

		throw "No target selected; use --ocaml, Haxe --js <file>, --ocaml-eval, or --compat.";
	}

	static function hasFlag(args:Array<String>, flag:String):Bool {
		return args.indexOf(flag) != -1;
	}

	static function findFlagValue(args:Array<String>, flag:String):Null<String> {
		var i = 0;
		while (i < args.length) {
			if (args[i] == flag) {
				if (i + 1 < args.length)
					return args[i + 1];
				return null;
			}
			i += 1;
		}
		return null;
	}

	static function hasDefine(args:Array<String>, name:String):Bool {
		return getDefineValue(args, name) != null;
	}

	static function getDefineValue(args:Array<String>, name:String):Null<String> {
		var i = 0;
		while (i < args.length) {
			final a = args[i];
			if (a == "-D" && i + 1 < args.length) {
				final d = args[i + 1];
				if (d == name)
					return "1";
				if (StringTools.startsWith(d, name + "="))
					return d.substr((name + "=").length);
				i += 2;
				continue;
			}
			i++;
		}
		return null;
	}

	static function addDefineIfMissing(args:Array<String>, define:String):Void {
		final eq = define.indexOf("=");
		final name = eq == -1 ? define : define.substr(0, eq);
		if (hasDefine(args, name))
			return;
		args.push("-D");
		args.push(define);
	}

	static function hasLibrary(args:Array<String>, name:String):Bool {
		var i = 0;
		while (i < args.length) {
			final a = args[i];
			if ((a == "-lib" || a == "--library") && i + 1 < args.length && args[i + 1] == name)
				return true;
			i += 1;
		}
		return false;
	}

	static function addLibraryIfMissing(args:Array<String>, name:String):Void {
		if (hasLibrary(args, name))
			return;
		args.push("--library");
		args.push(name);
	}

	static function hasMacro(args:Array<String>, macroExpr:String):Bool {
		var i = 0;
		while (i < args.length) {
			if (args[i] == "--macro" && i + 1 < args.length && args[i + 1] == macroExpr)
				return true;
			i += 1;
		}
		return false;
	}

	static function addMacroIfMissing(args:Array<String>, macroExpr:String):Void {
		if (hasMacro(args, macroExpr))
			return;
		args.push("--macro");
		args.push(macroExpr);
	}

	static function consumesStandardTargetValue(flag:String):Bool {
		return switch (flag) {
			case "-js" | "--js" | "-lua" | "--lua" | "-python" | "--python" | "-php" | "--php" | "-neko" | "--neko" | "-cpp" | "--cpp" | "-cs" | "--cs" |
				"-java" | "--java" | "-jvm" | "--jvm" | "-hl" | "--hl" | "-swf" | "--swf" | "-as3" | "--as3" | "-xml" | "--xml":
				true;
			case _:
				false;
		};
	}

	static function scanStandardTargetFlags(args:Array<String>):StandardTargetScan {
		var hasJs = false;
		var hasNonJs = false;
		var hasLegacy = false;
		var missingValueFlag:Null<String> = null;
		var i = 0;
		while (i < args.length) {
			final a = args[i];
			switch (a) {
				case "-js", "--js":
					hasJs = true;
				case "-swf", "--swf", "-as3", "--as3":
					hasNonJs = true;
					hasLegacy = true;
				case "-lua", "--lua", "-python", "--python", "-php", "--php", "-neko", "--neko", "-cpp", "--cpp", "-cs", "--cs", "-java", "--java", "-jvm",
					"--jvm", "-hl", "--hl", "-xml", "--xml":
					hasNonJs = true;
				case _:
			}
			if (consumesStandardTargetValue(a)) {
				if (i + 1 >= args.length) {
					missingValueFlag = a;
					break;
				}
				i += 2;
				continue;
			}
			i += 1;
		}
		return {
			hasJs: hasJs,
			hasNonJs: hasNonJs,
			hasLegacy: hasLegacy,
			missingValueFlag: missingValueFlag
		};
	}

	static function stripRoutingFlags(args:Array<String>):Array<String> {
		final out = new Array<String>();
		for (a in args) {
			switch (a) {
				case "--compat", "--ocaml", "--ocaml-eval":
				case _:
					out.push(a);
			}
		}
		return out;
	}

	static function planningTargetArgs(forwarded:Array<String>):Array<String> {
		final expanded = Stage1Args.expandHxmlArgs(forwarded);
		return expanded == null ? forwarded : expanded;
	}

	static function findUnsupportedLegacyTarget(args:Array<String>):Null<String> {
		for (a in args) {
			switch (a) {
				case "-swf", "--swf":
					return "flash";
				case "-as3", "--as3":
					return "as3";
				case _:
			}
		}
		return null;
	}
}
