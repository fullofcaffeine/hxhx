package hxhx;

import backend.EmitResult;
import haxe.io.Path;

/**
	Stage3 runtime command and hook helpers.

	Why
	- `Stage3Compiler` still owned several small but noisy helpers for safe command
	  parsing, cwd-scoped execution, and target-specific post-emit run hooks.
	- Those helpers are execution support glue, not compiler orchestration.

	What
	- Detects whether `node` is runnable.
	- Parses safe `java -jar ...` and `python ...` command forms.
	- Executes safe command-only hooks and artifact-matched hooks from a specific cwd.
	- Runs or skips emitted Stage3 artifacts after backend dispatch.

	How
	- The support module stays deliberately narrow and only exposes the helper
	  surface `Stage3Compiler` already uses today.
**/
class Stage3RunSupport {
	public static function canRunNode():Bool {
		try {
			final p = new sys.io.Process("node", ["--version"]);
			final code = p.exitCode();
			p.close();
			return code == 0;
		} catch (_:haxe.io.Error) {
			return false;
		} catch (_:String) {
			return false;
		}
	}

	public static function runSafeCommandOnlyHooks(commands:Array<String>, cwd:String):Null<Int> {
		if (commands == null || commands.length == 0)
			return null;
		var ran = false;
		for (command in commands) {
			final javaJar = parseSafeJavaJarCommand(command);
			final lua = parseSafeLuaCommand(command);
			final haxelibDev = parseSafeHaxelibDevCommand(command);
			var code:Null<Int> = null;
			if (javaJar != null) {
				code = runCommandInCwd("java", ["-jar", javaJar], cwd);
			} else if (lua != null) {
				code = runCommandInCwd(lua.command, lua.args, cwd);
			} else if (haxelibDev != null) {
				code = runCommandInCwd("haxelib", ["dev", haxelibDev.lib, haxelibDev.path], cwd);
			} else {
				return null;
			}
			if (code != 0)
				return code;
			ran = true;
		}
		return ran ? 0 : null;
	}

	public static function runCommandOnlyUnit(parsedHadCmd:Bool, parsedCmdCommands:Array<String>, cwd:String):Null<String> {
		if (!parsedHadCmd)
			return "missing -main <TypeName>";
		final cmdCode = runSafeCommandOnlyHooks(parsedCmdCommands, cwd);
		if (cmdCode != null) {
			if (cmdCode != 0)
				return "command hook failed with exit code " + Std.string(cmdCode);
			Sys.println("stage3=cmd_ok");
			return null;
		}
		Sys.println("stage3=skipped_cmd_only");
		return null;
	}

	public static function runSafeJavaJarHookForArtifact(commands:Array<String>, cwd:String, artifactPath:String):Null<Int> {
		if (commands == null || commands.length == 0 || artifactPath == null || artifactPath.length == 0)
			return null;
		final artifactAbs = Path.normalize(artifactPath);
		var matched:Null<String> = null;
		for (command in commands) {
			final javaJar = parseSafeJavaJarCommand(command);
			if (javaJar == null)
				return null;
			final jarAbs = Path.normalize(absFromCwd(cwd, javaJar));
			if (jarAbs == artifactAbs) {
				matched = javaJar;
				break;
			}
		}
		if (matched == null)
			return null;
		return runCommandInCwd("java", ["-jar", matched], cwd);
	}

	public static function runSafePythonHookForArtifact(commands:Array<String>, cwd:String, artifactPath:String):Null<Int> {
		if (commands == null || commands.length == 0 || artifactPath == null || artifactPath.length == 0)
			return null;
		final artifactAbs = Path.normalize(artifactPath);
		var matched:Null<{command:String, script:String}> = null;
		for (command in commands) {
			final python = parseSafePythonScriptCommand(command);
			if (python == null)
				return null;
			final scriptAbs = Path.normalize(absFromCwd(cwd, python.script));
			if (scriptAbs == artifactAbs) {
				matched = python;
				break;
			}
		}
		if (matched == null)
			return null;
		return runCommandInCwd(matched.command, [matched.script], cwd);
	}

	public static function runSafeNekoHookForArtifact(commands:Array<String>, cwd:String, artifactPath:String):Null<Int> {
		if (commands == null || commands.length == 0 || artifactPath == null || artifactPath.length == 0)
			return null;
		final artifactAbs = Path.normalize(artifactPath);
		var matched:Null<String> = null;
		for (command in commands) {
			final neko = parseSafeNekoCommand(command);
			if (neko == null)
				return null;
			final moduleAbs = Path.normalize(absFromCwd(cwd, neko));
			if (moduleAbs == artifactAbs) {
				matched = neko;
				break;
			}
		}
		if (matched == null)
			return null;
		return runCommandInCwd("neko", [matched], cwd);
	}

	public static function runSafeLuaCommands(commands:Array<String>, cwd:String):Null<Int> {
		if (commands == null || commands.length == 0)
			return null;
		var ran = false;
		for (command in commands) {
			final lua = parseSafeLuaCommand(command);
			if (lua == null)
				return null;
			final code = runCommandInCwd(lua.command, lua.args, cwd);
			if (code != 0)
				return code;
			ran = true;
		}
		return ran ? 0 : null;
	}

	public static function runEmittedArtifact(backendId:String, parsedHadCmd:Bool, parsedCmdCommands:Array<String>, parsedHadRun:Bool,
			parsedRunArgs:Array<String>, cwd:String, emitted:EmitResult, noRun:Bool):Null<String> {
		if (noRun) {
			Sys.println("run=skipped");
			return null;
		}

		if (!emitted.builtExecutable) {
			if (backendId == "java-native" && parsedHadCmd) {
				final cmdCode = runSafeJavaJarHookForArtifact(parsedCmdCommands, cwd, emitted.entryPath);
				if (cmdCode != null) {
					if (cmdCode != 0)
						return "command hook failed with exit code " + Std.string(cmdCode);
					Sys.println("stage3=cmd_ok");
					return null;
				}
			}
			if (backendId == "python-native" && parsedHadCmd) {
				final cmdCode = runSafePythonHookForArtifact(parsedCmdCommands, cwd, emitted.entryPath);
				if (cmdCode != null) {
					if (cmdCode != 0)
						return "command hook failed with exit code " + Std.string(cmdCode);
					Sys.println("stage3=cmd_ok");
					return null;
				}
			}
			if (backendId == "neko-native" && parsedHadCmd) {
				final cmdCode = runSafeNekoHookForArtifact(parsedCmdCommands, cwd, emitted.entryPath);
				if (cmdCode != null) {
					if (cmdCode != 0)
						return "command hook failed with exit code " + Std.string(cmdCode);
					return null;
				}
			}
			if (backendId == "lua-native") {
				if (parsedHadCmd) {
					final cmdCode = runSafeLuaCommands(parsedCmdCommands, cwd);
					if (cmdCode != null) {
						if (cmdCode != 0)
							return "command hook failed with exit code " + Std.string(cmdCode);
						return null;
					}
				}
				if (parsedHadRun) {
					final luaCode = runCommandInCwd("lua", [emitted.entryPath].concat(parsedRunArgs == null ? [] : parsedRunArgs), cwd);
					if (luaCode != 0)
						return "lua run failed with exit code " + luaCode;
					return null;
				}
			}
			if (backendId == "js-native") {
				if (!canRunNode()) {
					Sys.println("run=skipped_node_missing");
					return null;
				}
				final jsCode = Sys.command("node", [emitted.entryPath]);
				if (jsCode != 0)
					return "node run failed with exit code " + jsCode;
				Sys.println("run=ok");
				return null;
			}
			Sys.println("run=skipped_non_executable_backend");
			return null;
		}

		final code = Sys.command(emitted.entryPath, []);
		if (code != 0)
			return "built executable failed with exit code " + code;
		Sys.println("run=ok");
		return null;
	}

	static function parseSafeJavaJarCommand(command:String):Null<String> {
		final words = splitCommandWords(command);
		if (words.length != 3)
			return null;
		if (words[0] != "java" || words[1] != "-jar")
			return null;
		final jar = words[2];
		if (jar.length == 0 || jar.indexOf(";") >= 0 || jar.indexOf("&&") >= 0 || jar.indexOf("|") >= 0)
			return null;
		return jar;
	}

	static function parseSafePythonScriptCommand(command:String):Null<{command:String, script:String}> {
		final words = splitCommandWords(command);
		if (words.length != 2)
			return null;
		final runner = words[0];
		if (runner != "python3" && runner != "python" && runner != "pypy3")
			return null;
		final script = words[1];
		if (script.length == 0 || script.indexOf(";") >= 0 || script.indexOf("&&") >= 0 || script.indexOf("|") >= 0)
			return null;
		return {command: runner, script: script};
	}

	static function parseSafeNekoCommand(command:String):Null<String> {
		final words = splitCommandWords(command);
		if (words.length != 2)
			return null;
		if (words[0] != "neko")
			return null;
		final module = words[1];
		if (!isSafeCommandWord(module) || StringTools.startsWith(module, "-"))
			return null;
		return module;
	}

	static function parseSafeLuaCommand(command:String):Null<{command:String, args:Array<String>}> {
		final words = splitCommandWords(command);
		if (words.length < 2)
			return null;
		final runner = words[0];
		if (runner != "lua" && runner != "luajit")
			return null;
		for (word in words) {
			if (!isSafeCommandWord(word))
				return null;
		}
		return {command: runner, args: words.slice(1)};
	}

	static function parseSafeHaxelibDevCommand(command:String):Null<{lib:String, path:String}> {
		final words = splitCommandWords(command);
		if (words.length != 4)
			return null;
		if (words[0] != "haxelib" || words[1] != "dev")
			return null;
		final lib = words[2];
		final path = words[3];
		if (!isSafeCommandWord(lib) || !isSafeCommandWord(path))
			return null;
		if (StringTools.startsWith(lib, "-") || StringTools.startsWith(path, "-"))
			return null;
		return {lib: lib, path: path};
	}

	static function isSafeCommandWord(word:String):Bool {
		return word != null && word.length > 0 && word.indexOf(";") < 0 && word.indexOf("&&") < 0 && word.indexOf("|") < 0 && word.indexOf("`") < 0
			&& word.indexOf("$(") < 0;
	}

	static function splitCommandWords(command:String):Array<String> {
		final out = new Array<String>();
		if (command == null)
			return out;
		var current = new StringBuf();
		var quote = 0;
		var i = 0;
		while (i < command.length) {
			final ch = command.charCodeAt(i);
			if (quote == 0 && (ch == " ".code || ch == "\t".code || ch == "\r".code || ch == "\n".code)) {
				if (current.length > 0) {
					out.push(current.toString());
					current = new StringBuf();
				}
			} else if (ch == "\"".code || ch == "'".code) {
				if (quote == 0) {
					quote = ch;
				} else if (quote == ch) {
					quote = 0;
				} else {
					current.addChar(ch);
				}
			} else {
				current.addChar(ch);
			}
			i += 1;
		}
		if (current.length > 0)
			out.push(current.toString());
		return out;
	}

	static function absFromCwd(cwd:String, path:String):String {
		if (path == null || path.length == 0)
			return cwd;
		return Path.isAbsolute(path) ? Path.normalize(path) : Path.normalize(Path.join([cwd, path]));
	}

	static function runCommandInCwd(command:String, args:Array<String>, cwd:String):Int {
		final previous = Sys.getCwd();
		try {
			Sys.setCwd(cwd);
			final code = Sys.command(command, args);
			Sys.setCwd(previous);
			return code;
		} catch (e:haxe.Exception) {
			Sys.setCwd(previous);
			throw e;
		} catch (raw:String) {
			Sys.setCwd(previous);
			throw raw;
		}
	}
}
