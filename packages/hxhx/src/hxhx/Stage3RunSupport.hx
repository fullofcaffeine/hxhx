package hxhx;

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
			if (javaJar == null)
				return null;
			final code = runCommandInCwd("java", ["-jar", javaJar], cwd);
			if (code != 0)
				return code;
			ran = true;
		}
		return ran ? 0 : null;
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
