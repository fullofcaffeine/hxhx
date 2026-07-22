package hxhx;

import hxhx.Stage1Compiler.Stage1Args;

/**
	Stage3-specific argument normalization helpers.

	Why
	- `Stage3Compiler` needs normalized Stage3 flags and target output hints, but
	  the parsing rules themselves are stable helper logic rather than execution
	  orchestration.

	What
	- Parses `--hxhx-*` Stage3 control flags.
	- Removes the opt-in `--hxhx-server-report` flag before ordinary Haxe argument
	  parsing; the request context owns that lifecycle report.
	- Maps backend IDs to target define/output hint behavior.
	- Summarizes per-unit forwarded arguments for trace logging.
	- Detects whether a flag is already present in a forwarded arg vector.

	How
	- This module does not execute compilation work. It only normalizes argv and
	  target-specific output hint state so `Stage3Compiler` can stay focused on
	  orchestration and backend dispatch.
**/
class Stage3Args {
	public static function hasFlag(args:Array<String>, flag:String):Bool {
		if (args == null || flag == null || flag.length == 0)
			return false;
		for (a in args)
			if (a == flag)
				return true;
		return false;
	}

	public static function parseGlobalStage3Flags(args:Array<String>) {
		var outDir = "";
		var backendId = "ocaml-stage3";
		var macroRuntimeMode:Null<String> = null;
		var typeOnly = false;
		var emitFullBodies = false;
		var noEmit = false;
		var noRun = false;
		var serverReport = false;
		final customizations = new Array<String>();
		final rest = new Array<String>();

		var i = 0;
		while (i < args.length) {
			final a = args[i];
			switch (a) {
				case "--hxhx-out":
					if (i + 1 >= args.length)
						throw "missing value after --hxhx-out";
					outDir = args[i + 1];
					i += 2;
				case "--hxhx-backend":
					if (i + 1 >= args.length)
						throw "missing value after --hxhx-backend";
					backendId = args[i + 1];
					i += 2;
				case "--hxhx-macro-runtime":
					if (i + 1 >= args.length)
						throw "missing value after --hxhx-macro-runtime";
					macroRuntimeMode = args[i + 1];
					i += 2;
				case "--hxhx-customization":
					if (i + 1 >= args.length)
						throw "missing value after --hxhx-customization";
					customizations.push(args[i + 1]);
					i += 2;
				case "--hxhx-type-only":
					typeOnly = true;
					i += 1;
				case "--hxhx-no-emit":
					noEmit = true;
					i += 1;
				case "--hxhx-no-run":
					noRun = true;
					i += 1;
				case "--hxhx-server-report":
					serverReport = true;
					i += 1;
				case "--hxhx-emit-full-bodies":
					emitFullBodies = true;
					i += 1;
				case _:
					rest.push(a);
					i += 1;
			}
		}

		return {
			outDir: outDir,
			backendId: backendId,
			macroRuntimeMode: macroRuntimeMode,
			typeOnly: typeOnly,
			emitFullBodies: emitFullBodies,
			noEmit: noEmit,
			noRun: noRun,
			serverReport: serverReport,
			customizations: customizations,
			rest: rest
		};
	}

	public static function targetDefineForBackend(backendId:String):String {
		return switch (backendId) {
			case "js-native":
				"js";
			case "neko-native":
				"neko";
			case "hl-native":
				"hl";
			case "cpp-native":
				"cpp";
			case "python-native":
				"python";
			case "java-native":
				"java";
			case "cs-native":
				"cs";
			case "php-native":
				"php";
			case "lua-native":
				"lua";
			case _:
				"ocaml";
		};
	}

	static function targetOutputFlags(backendId:String):Array<String> {
		return switch (backendId) {
			case "js-native":
				["-js", "--js"];
			case "neko-native":
				["-neko", "--neko"];
			case "hl-native":
				["-hl", "--hl"];
			case "python-native":
				["-python", "--python"];
			case "lua-native":
				["-lua", "--lua"];
			case "java-native":
				["-jvm", "--jvm"];
			case _:
				[];
		};
	}

	static function targetOutputDirectoryFlags(backendId:String):Array<String> {
		return switch (backendId) {
			case "java-native":
				["-java", "--java"];
			case "cs-native":
				["-cs", "--cs"];
			case "php-native":
				["-php", "--php"];
			case "cpp-native":
				["-cpp", "--cpp"];
			case _:
				[];
		};
	}

	public static function findTargetOutputFileHint(args:Array<String>, backendId:String):Null<String> {
		final expanded = Stage1Args.expandHxmlArgs(args);
		if (expanded == null)
			return null;
		final targetFlags = targetOutputFlags(backendId);
		if (targetFlags.length == 0)
			return null;
		var i = 0;
		while (i < expanded.length) {
			final a = expanded[i];
			if (targetFlags.indexOf(a) >= 0) {
				if (i + 1 < expanded.length)
					return expanded[i + 1];
				return null;
			}
			i += 1;
		}
		return null;
	}

	public static function findTargetOutputDirectoryHint(args:Array<String>, backendId:String):Null<String> {
		final expanded = Stage1Args.expandHxmlArgs(args);
		if (expanded == null)
			return null;
		final targetFlags = targetOutputDirectoryFlags(backendId);
		if (targetFlags.length == 0)
			return null;
		var i = 0;
		while (i < expanded.length) {
			final a = expanded[i];
			if (targetFlags.indexOf(a) >= 0) {
				if (i + 1 < expanded.length)
					return expanded[i + 1];
				return null;
			}
			i += 1;
		}
		return null;
	}

	public static function initialRoots(parsedMain:Null<String>, parsedRoots:Array<String>,
			parsedMacros:Array<String>):{roots:Array<String>, missingMainFromMacro:Bool} {
		final roots = new Array<String>();
		if (parsedMain != null && parsedMain.length > 0) {
			roots.push(parsedMain);
		} else if (parsedRoots != null && parsedRoots.length > 0) {
			for (r in parsedRoots)
				if (r != null && r.length > 0)
					roots.push(r);
		} else if (parsedMacros.length > 0) {
			final inferred = Stage3PathSupport.inferMainFromMacroExpr(parsedMacros[0]);
			if (inferred.length == 0)
				return {roots: roots, missingMainFromMacro: true};
			roots.push(inferred);
		}
		return {roots: roots, missingMainFromMacro: false};
	}

	public static function findFlagValue(args:Array<String>, a:String, b:String):Null<String> {
		var i = 0;
		while (i < args.length) {
			final t = args[i];
			if ((t == a || t == b) && i + 1 < args.length)
				return args[i + 1];
			i++;
		}
		return null;
	}

	public static function findManyFlagValues(args:Array<String>, a:String, b:String, ?c:String):Array<String> {
		final out = new Array<String>();
		var i = 0;
		while (i < args.length) {
			final t = args[i];
			final match = (t == a || t == b || (c != null && t == c));
			if (match && i + 1 < args.length) {
				out.push(args[i + 1]);
				i += 2;
				continue;
			}
			i++;
		}
		return out;
	}

	public static function summarizeArgs(args:Array<String>):String {
		final joined = args.join(" ");
		final maxLen = 160;
		if (joined.length <= maxLen)
			return joined;
		return joined.substr(0, maxLen) + "...";
	}
}
