package hxhx.macro;

private typedef RuntimeResolvedTypeSnapshot = {
	final name:String;
	final kind:String;
	final metadata:Array<String>;
	final typeParamNames:Array<String>;
	final underlyingTypeText:Null<String>;
	final staticFields:Array<RuntimeResolvedModuleFieldSnapshot>;
	final file:String;
	final min:Int;
	final max:Int;
}

private typedef RuntimeResolvedTypeSemantics = {
	final typeParamNames:Array<String>;
	final underlyingTypeText:Null<String>;
}

private typedef RuntimeResolvedModuleFieldSnapshot = {
	final name:String;
	final kind:String;
	final metadata:Array<String>;
	final initExpr:Null<String>;
	final args:Array<{
		final name:String;
		final opt:Bool;
		final typeText:String;
	}>;
	final returnTypeText:Null<String>;
	final file:String;
	final min:Int;
	final max:Int;
}

private enum MacroHostReadResult {
	ReadLine(line:String);
	ReadEof;
	ReadError(message:String);
}

/**
	Macro host RPC client (Stage 4, Model A).

	Why
	- Stage 4 starts executing macros natively.
	- Model A runs macros out-of-process and communicates via a versioned protocol.
	- This bead’s objective is **not** to run real user macros yet; it is to prove
	  the ABI boundary exists and is testable:
	  - spawn a macro host process
	  - complete a handshake
	  - invoke a couple of stubbed `Context.*` / `Compiler.*`-shaped calls

	What
	- `selftest()` is a deterministic acceptance probe used by CI:
	  - launches `hxhx-macro-host`
	  - performs the handshake
	  - runs stub calls (`ping`, `compiler.define`, `context.defined`, `context.definedValue`)
	  - returns a stable multi-line summary for grep-based assertions

	How
	- The protocol encoding lives in `MacroProtocol` (pure Haxe).
	- The transport uses `sys.io.Process` to spawn the macro host and communicate
	  via stdin/stdout.
	- On the OCaml target, `sys.io.Process` is provided by an override in
	  `std/_std/sys/io/Process.hx` backed by the small OCaml runtime shim
	  `std/runtime/HxProcess.ml`.
	- This keeps the compiler + protocol logic in Haxe while allowing early
	  bring-up on OCaml with strict dune warning/error settings.
**/
class MacroHostClient {
	static function withClient<T>(run:MacroClient->T):T {
		final client = connect();
		try {
			final out = run(client);
			client.close();
			return out;
		} catch (e:String) {
			client.close();
			throw e;
		}
	}

	static function withSession<T>(run:MacroHostSession->T):T {
		final session = openSession();
		try {
			final out = run(session);
			session.close();
			return out;
		} catch (e:String) {
			session.close();
			throw e;
		}
	}

	/**
		Resolve the macro host executable path as `hxhx` sees it.

		Why
		- Stage 4 macro execution is an out-of-process model (RPC macro host).
		- For distribution, we want `hxhx` to “just work” when a sibling `hxhx-macro-host`
		  executable exists next to the `hxhx` binary.
		- For development/CI, we still allow overriding with `HXHX_MACRO_HOST_EXE`.

		What
		- Returns an absolute path when possible.
		- Returns `""` if no macro host can be resolved.

		Gotchas
		- This is a best-effort heuristic; callers should treat `""` as “not available”.
	**/
	public static function resolveMacroHostExePath():String {
		return resolveMacroHostExe();
	}

	public static function selftest():String {
		return withClient(function(client) {
			final lines = new Array<String>();
			lines.push("macro_host=ok");
			lines.push("macro_ping=" + client.call("ping", ""));
			lines.push("macro_define=" + client.call("compiler.define", MacroProtocol.encodeLen("n", "foo") + " " + MacroProtocol.encodeLen("v", "bar")));
			lines.push("macro_defined=" + (client.call("context.defined", MacroProtocol.encodeLen("n", "foo")) == "1" ? "yes" : "no"));
			lines.push("macro_definedValue=" + client.call("context.definedValue", MacroProtocol.encodeLen("n", "foo")));
			return lines.join("\n");
		});
	}

	public static function run(expr:String):String {
		return withClient(function(client) {
			return client.call("macro.run", MacroProtocol.encodeLen("e", expr));
		});
	}

	public static function loadNativeModule(modulePath:String, pluginId:String):Array<String> {
		return withSession(function(session) {
			return session.loadNativeModule(modulePath, pluginId);
		});
	}

	public static function runNativeModuleExpr(modulePath:String, pluginId:String, expr:String):String {
		return withSession(function(session) {
			session.loadNativeModule(modulePath, pluginId);
			return session.runNativeExpr(expr);
		});
	}

	/**
		Open a macro host session for a full compilation.

		Why
		- Hook registration (`Context.onAfterTyping`, `Context.onGenerate`) stores closures inside
		  the macro host process, so the session must remain alive until those hooks are invoked.
	**/
	public static function openSession():MacroHostSession {
		return new MacroHostSession(connect());
	}

	/**
		Run multiple macro expressions in a single macro-host session.

		Why
		- Even the earliest Stage 4 rungs need to exercise “real CLI macro” behavior (`--macro`),
		  which may include multiple macro expressions.
		- Spawning a macro host per expression is slow and makes ordering/state harder to reason about.
		- A single session also better matches the long-term “macro server” behavior upstream uses.

		What
		- Spawns one macro host process
		- Executes `macro.run` for each expression in order
		- Returns the list of `v=` payload strings (same as `run(expr)`)

		Gotchas
		- This is still a bring-up API: expressions are currently allowlisted on the server side.
		- The macro host is currently expected to be a fresh process per compilation; later stages
		  may add reuse/caching.
	**/
	public static function runAll(exprs:Array<String>):Array<String> {
		return withSession(function(session) {
			final out = new Array<String>();
			for (expr in exprs)
				out.push(session.run(expr));
			return out;
		});
	}

	public static function getType(name:String):String {
		return withClient(function(client) {
			return client.call("context.getType", MacroProtocol.encodeLen("n", name));
		});
	}

	public static function decodeNativeExprListPayload(payload:String):Array<String> {
		final parts = MacroProtocol.kvParse(payload == null ? "" : payload);
		final countStr = parts.exists("c") ? parts.get("c") : "0";
		final count = Std.parseInt(countStr);
		if (count == null || count < 0)
			throw "macro host: invalid native module expr count payload: " + countStr;
		final out = new Array<String>();
		for (i in 0...count) {
			final key = "e" + i;
			if (!parts.exists(key))
				throw "macro host: missing native module expr payload key: " + key;
			out.push(parts.get(key));
		}
		return out;
	}

	static function resolveMacroHostExe():String {
		final env = Sys.getEnv("HXHX_MACRO_HOST_EXE");
		if (env != null && env.length > 0)
			return env;

		// Distribution-friendly default: if `hxhx-macro-host` is shipped next to the `hxhx` binary,
		// discover it automatically so users don't have to set `HXHX_MACRO_HOST_EXE`.
		//
		// This is a best-effort heuristic:
		// - If `Sys.programPath()` is unavailable or points somewhere unexpected, we fall back to "".
		// - The env var always wins (useful for local dev or non-standard layouts).
		final prog = Sys.programPath();
		if (prog == null || prog.length == 0)
			return "";

		final abs = try sys.FileSystem.fullPath(prog) catch (_:String) prog;
		final dir = try haxe.io.Path.directory(abs) catch (_:String) "";
		if (dir == null || dir.length == 0)
			return "";

		final candidates = ["hxhx-macro-host", "hxhx-macro-host.exe", "hxhx-macro", "hxhx-macro.exe",];
		for (name in candidates) {
			final p = haxe.io.Path.join([dir, name]);
			try {
				if (sys.FileSystem.exists(p) && !sys.FileSystem.isDirectory(p))
					return p;
			} catch (_:String) {}
		}

		return "";
	}

	static function gatherCurrentDefines():Array<String> {
		final out = new Array<String>();
		for (pair in MacroState.listDefinesPairsSorted()) {
			if (pair == null || pair.length == 0)
				continue;
			final key = pair[0];
			if (key == null || key.length == 0)
				continue;
			final value = pair.length > 1 ? pair[1] : "1";
			out.push(value == "1" ? key : (key + "=" + value));
		}
		return out;
	}

	static function readFilteredResolvedModuleSource(path:String):String {
		final source = try sys.io.File.getContent(path) catch (_:haxe.io.Error) {
			null;
		} catch (_:String) {
			null;
		}
		if (source == null || source.length == 0)
			return "";
		final defines = HxDefineMap.fromRawDefines(gatherCurrentDefines());
		return HxConditionalCompilation.filterSource(source, defines);
	}

	static function splitLinesPreserveNewlines(source:String):Array<String> {
		final out = new Array<String>();
		var start = 0;
		var i = 0;
		while (i < source.length) {
			if (source.charCodeAt(i) == "\n".code) {
				out.push(source.substr(start, i - start + 1));
				i += 1;
				start = i;
				continue;
			}
			i += 1;
		}
		if (start < source.length)
			out.push(source.substr(start));
		return out;
	}

	static function scanResolvedTypeStaticFields(path:String, typeName:String, kind:String):Array<RuntimeResolvedModuleFieldSnapshot> {
		final filtered = readFilteredResolvedModuleSource(path);
		if (filtered.length == 0)
			return [];

		final normalizedKind = StringTools.trim(kind == null ? "" : kind).toLowerCase();
		if (normalizedKind != "class" && normalizedKind != "abstract")
			return [];

		function lineSpan(rawLine:String, start:Int):{min:Int, max:Int} {
			var min = 0;
			while (min < rawLine.length) {
				final c = rawLine.charCodeAt(min);
				if (c == " ".code || c == "\t".code)
					min += 1;
				else
					break;
			}
			var max = rawLine.length;
			while (max > min) {
				final c = rawLine.charCodeAt(max - 1);
				if (c == "\n".code || c == "\r".code)
					max -= 1;
				else
					break;
			}
			return {
				min: start + min,
				max: start + max
			};
		}

		function stripLineComments(text:String):String {
			var inString = false;
			var quote = "";
			var i = 0;
			while (i < text.length - 1) {
				final ch = text.charAt(i);
				if (inString) {
					if (ch == "\\") {
						i += 2;
						continue;
					}
					if (ch == quote)
						inString = false;
					i += 1;
					continue;
				}
				if (ch == "\"" || ch == "'") {
					inString = true;
					quote = ch;
					i += 1;
					continue;
				}
				if (ch == "/" && text.charAt(i + 1) == "/")
					return text.substr(0, i);
				i += 1;
			}
			return text;
		}

		function extractName(prefix:String, keyword:String):String {
			final rest = StringTools.trim(prefix.substr(keyword.length));
			if (rest.length == 0)
				return "";
			final match = ~/^([A-Za-z_][A-Za-z0-9_]*)/;
			return match.match(rest) ? match.matched(1) : "";
		}

		function extractInitializer(prefix:String, keyword:String):Null<String> {
			final rest = StringTools.trim(prefix.substr(keyword.length));
			if (rest.length == 0)
				return null;
			final nameMatch = ~/^([A-Za-z_][A-Za-z0-9_]*)/;
			if (!nameMatch.match(rest))
				return null;
			final afterName = StringTools.trim(rest.substr(nameMatch.matchedPos().pos + nameMatch.matchedPos().len));
			if (afterName.length == 0)
				return null;
			final eqIndex = afterName.indexOf("=");
			if (eqIndex < 0)
				return null;
			var exprText = StringTools.trim(afterName.substr(eqIndex + 1));
			if (exprText.length == 0)
				return null;
			if (StringTools.endsWith(exprText, ";"))
				exprText = StringTools.trim(exprText.substr(0, exprText.length - 1));
			return exprText.length == 0 ? null : exprText;
		}

		function splitTopLevelComma(text:String):Array<String> {
			final out = new Array<String>();
			if (text == null)
				return out;
			var start = 0;
			var parenDepth = 0;
			var bracketDepth = 0;
			var braceDepth = 0;
			var angleDepth = 0;
			var inString = false;
			var quote = "";
			var i = 0;
			while (i < text.length) {
				final ch = text.charAt(i);
				if (inString) {
					if (ch == "\\") {
						i += 2;
						continue;
					}
					if (ch == quote)
						inString = false;
					i += 1;
					continue;
				}
				switch (ch) {
					case "\"" | "'":
						inString = true;
						quote = ch;
					case "(":
						parenDepth += 1;
					case ")":
						if (parenDepth > 0)
							parenDepth -= 1;
					case "[":
						bracketDepth += 1;
					case "]":
						if (bracketDepth > 0)
							bracketDepth -= 1;
					case "{":
						braceDepth += 1;
					case "}":
						if (braceDepth > 0)
							braceDepth -= 1;
					case "<":
						angleDepth += 1;
					case ">":
						if (angleDepth > 0)
							angleDepth -= 1;
					case ",":
						if (parenDepth == 0 && bracketDepth == 0 && braceDepth == 0 && angleDepth == 0) {
							out.push(text.substr(start, i - start));
							start = i + 1;
						}
					case _:
				}
				i += 1;
			}
			out.push(text.substr(start));
			return out;
		}

		function parseFunctionArgs(text:String):Array<{name:String, opt:Bool, typeText:String}> {
			final out = new Array<{name:String, opt:Bool, typeText:String}>();
			for (segment in splitTopLevelComma(text)) {
				final trimmed = StringTools.trim(segment);
				if (trimmed.length == 0)
					continue;
				var working = trimmed;
				var optional = false;
				if (StringTools.startsWith(working, "?")) {
					optional = true;
					working = StringTools.trim(working.substr(1));
				}
				final nameMatch = ~/^([A-Za-z_][A-Za-z0-9_]*)/;
				if (!nameMatch.match(working))
					continue;
				final name = nameMatch.matched(1);
				var afterName = StringTools.trim(working.substr(nameMatch.matchedPos().pos + nameMatch.matchedPos().len));
				var typeText = "Dynamic";
				final eqIndex = afterName.indexOf("=");
				if (eqIndex >= 0) {
					optional = true;
					afterName = StringTools.trim(afterName.substr(0, eqIndex));
				}
				if (StringTools.startsWith(afterName, ":")) {
					final parsedType = StringTools.trim(afterName.substr(1));
					if (parsedType.length > 0)
						typeText = parsedType;
				}
				out.push({
					name: name,
					opt: optional,
					typeText: typeText
				});
			}
			return out;
		}

		function parseFunctionSignature(prefix:String):{
			args:Array<{name:String, opt:Bool, typeText:String}>,
			returnTypeText:Null<String>
		} {
			final signature = StringTools.trim(prefix.substr("function".length));
			final openParen = signature.indexOf("(");
			final closeParen = signature.lastIndexOf(")");
			if (openParen < 0 || closeParen < openParen)
				return {
					args: [],
					returnTypeText: null
				};
			final argsText = signature.substr(openParen + 1, closeParen - openParen - 1);
			var tail = StringTools.trim(signature.substr(closeParen + 1));
			var returnTypeText:Null<String> = null;
			if (StringTools.startsWith(tail, ":")) {
				tail = StringTools.trim(tail.substr(1));
				final braceIndex = tail.indexOf("{");
				if (braceIndex >= 0)
					tail = StringTools.trim(tail.substr(0, braceIndex));
				if (StringTools.endsWith(tail, ";"))
					tail = StringTools.trim(tail.substr(0, tail.length - 1));
				if (tail.length > 0)
					returnTypeText = tail;
			}
			return {
				args: parseFunctionArgs(argsText),
				returnTypeText: returnTypeText
			};
		}

		function countChar(text:String, ch:String):Int {
			var count = 0;
			var i = 0;
			while (i < text.length) {
				if (text.charAt(i) == ch)
					count += 1;
				i += 1;
			}
			return count;
		}

		function findTypeBodyStart():Int {
			var braceDepth = 0;
			var i = 0;
			while (true) {
				final t = ParserStageScanHelpers.scanNextToken(filtered, i);
				i = t.nextPos;
				if (t.text.length == 0)
					return -1;

				if (!t.isIdent) {
					if (t.text == "{")
						braceDepth += 1;
					else if (t.text == "}")
						braceDepth = braceDepth > 0 ? (braceDepth - 1) : 0;
					continue;
				}

				if (braceDepth != 0)
					continue;

				if (t.text == "enum") {
					var enumNameTok = ParserStageScanHelpers.scanNextToken(filtered, i);
					while (enumNameTok.text.length > 0 && !enumNameTok.isIdent)
						enumNameTok = ParserStageScanHelpers.scanNextToken(filtered, enumNameTok.nextPos);
					if (!enumNameTok.isIdent || enumNameTok.text.length == 0)
						continue;

					if (enumNameTok.text == "abstract") {
						enumNameTok = ParserStageScanHelpers.scanNextToken(filtered, enumNameTok.nextPos);
						while (enumNameTok.text.length > 0 && !enumNameTok.isIdent)
							enumNameTok = ParserStageScanHelpers.scanNextToken(filtered, enumNameTok.nextPos);
						if (!enumNameTok.isIdent || enumNameTok.text.length == 0)
							continue;
					}
					i = enumNameTok.nextPos;

					var enumHeaderTok = ParserStageScanHelpers.scanNextToken(filtered, i);
					while (enumHeaderTok.text.length > 0 && enumHeaderTok.text != "{" && enumHeaderTok.text != ";")
						enumHeaderTok = ParserStageScanHelpers.scanNextToken(filtered, enumHeaderTok.nextPos);
					if (enumHeaderTok.text == "{") {
						final scanned = ParserStageScanHelpers.scanEnumBodyForCtors(filtered, enumHeaderTok.nextPos);
						i = scanned.nextPos;
					} else if (enumHeaderTok.text.length > 0) {
						i = enumHeaderTok.nextPos;
					}
					continue;
				}

				if (t.text != normalizedKind)
					continue;

				var nameTok = ParserStageScanHelpers.scanNextToken(filtered, i);
				while (nameTok.text.length > 0 && !nameTok.isIdent)
					nameTok = ParserStageScanHelpers.scanNextToken(filtered, nameTok.nextPos);
				if (!nameTok.isIdent || nameTok.text.length == 0)
					continue;
				if (nameTok.text != typeName)
					continue;

				var headerTok = ParserStageScanHelpers.scanNextToken(filtered, nameTok.nextPos);
				while (headerTok.text.length > 0 && headerTok.text != "{" && headerTok.text != ";")
					headerTok = ParserStageScanHelpers.scanNextToken(filtered, headerTok.nextPos);
				return headerTok.text == "{" ? headerTok.nextPos : -1;
			}
			return -1;
		}

		final bodyStart = findTypeBodyStart();
		if (bodyStart < 0)
			return [];

		final out = new Array<RuntimeResolvedModuleFieldSnapshot>();
		final seen = new Map<String, Bool>();
		final lines = splitLinesPreserveNewlines(filtered.substr(bodyStart));
		var braceDepth = 1;
		var blockCommentDepth = 0;
		var lineOffset = bodyStart;
		var pendingMetadata = new Array<String>();

		function push(kind:String, name:String, span:{min:Int, max:Int}, ?initExpr:Null<String>, ?args:Array<{name:String, opt:Bool, typeText:String}>,
				?returnTypeText:Null<String>):Void {
			final trimmed = StringTools.trim(name == null ? "" : name);
			if (trimmed.length == 0 || seen.exists(trimmed))
				return;
			seen.set(trimmed, true);
			out.push({
				name: trimmed,
				kind: kind,
				metadata: pendingMetadata.copy(),
				initExpr: initExpr,
				args: args == null ? [] : args.copy(),
				returnTypeText: returnTypeText,
				file: path,
				min: span.min,
				max: span.max
			});
			pendingMetadata = [];
		}

		function hasStaticBefore(text:String, keywordIndex:Int):Bool {
			if (keywordIndex < 0)
				return false;
			return text.substr(0, keywordIndex).indexOf("static") >= 0;
		}

		for (rawLine in lines) {
			final currentLineOffset = lineOffset;
			lineOffset += rawLine.length;
			var line = rawLine;
			if (blockCommentDepth > 0) {
				while (line.length > 0 && blockCommentDepth > 0) {
					final close = line.indexOf("*/");
					if (close == -1) {
						line = "";
					} else {
						blockCommentDepth -= 1;
						line = line.substr(close + 2);
					}
				}
			}

			while (true) {
				final open = line.indexOf("/*");
				if (open == -1)
					break;
				final close = line.indexOf("*/", open + 2);
				if (close == -1) {
					blockCommentDepth += 1;
					line = line.substr(0, open);
					break;
				}
				line = line.substr(0, open) + line.substr(close + 2);
			}

			line = stripLineComments(line);
			final trimmed = StringTools.trim(line);
			if (trimmed.length == 0) {
				braceDepth += countChar(line, "{");
				braceDepth -= countChar(line, "}");
				if (braceDepth < 0)
					braceDepth = 0;
				if (braceDepth <= 1)
					pendingMetadata = [];
				continue;
			}

			if (braceDepth == 1) {
				final span = lineSpan(rawLine, currentLineOffset);
				if (StringTools.startsWith(trimmed, "@:")) {
					pendingMetadata.push(trimmed);
				} else {
					final functionIndex = trimmed.indexOf("function ");
					final varIndex = trimmed.indexOf("var ");
					final finalIndex = trimmed.indexOf("final ");
					if (functionIndex >= 0 && hasStaticBefore(trimmed, functionIndex)) {
						final signature = trimmed.substr(functionIndex);
						final parsed = parseFunctionSignature(signature);
						push("method", extractName(signature, "function"), span, null, parsed.args, parsed.returnTypeText);
					} else if (varIndex >= 0 && hasStaticBefore(trimmed, varIndex)) {
						final fieldDecl = trimmed.substr(varIndex);
						push("var", extractName(fieldDecl, "var"), span, extractInitializer(fieldDecl, "var"));
					} else if (finalIndex >= 0
						&& hasStaticBefore(trimmed, finalIndex)
						&& (functionIndex < 0 || finalIndex < functionIndex)) {
						final fieldDecl = trimmed.substr(finalIndex);
						push("final", extractName(fieldDecl, "final"), span, extractInitializer(fieldDecl, "final"));
					} else if (!StringTools.startsWith(trimmed, "#if")
						&& !StringTools.startsWith(trimmed, "#elseif")
						&& !StringTools.startsWith(trimmed, "#else")
						&& !StringTools.startsWith(trimmed, "#end")) {
						pendingMetadata = [];
					}
				}
			}

			braceDepth += countChar(line, "{");
			braceDepth -= countChar(line, "}");
			if (braceDepth < 0)
				braceDepth = 0;
			if (braceDepth <= 0)
				break;
		}

		return out;
	}

	public static function scanResolvedModuleTypes(modulePath:String, path:String, fallbackMainName:String,
			?includeFallbackMain:Bool = true):Array<RuntimeResolvedTypeSnapshot> {
		final out = new Array<RuntimeResolvedTypeSnapshot>();
		final seen = new Map<String, Bool>();
		final modulePack = modulePath == null ? [] : modulePath.split(".");
		if (modulePack.length > 0)
			modulePack.pop();
		final typeSpans = scanResolvedModuleTypeSpans(path);
		final typeSemantics = scanResolvedTypeSemantics(path);
		inline function fullTypePath(name:String):String {
			return modulePack.length == 0 ? name : modulePack.join(".") + "." + name;
		}
		inline function push(kind:String, name:String):Void {
			final trimmed = name == null ? "" : StringTools.trim(name);
			if (trimmed.length == 0 || seen.exists(trimmed))
				return;
			seen.set(trimmed, true);
			final span = typeSpans.exists(trimmed) ? typeSpans.get(trimmed) : {
				file: path,
				min: 0,
				max: 0
			};
			final semantics:RuntimeResolvedTypeSemantics = typeSemantics.exists(trimmed) ? typeSemantics.get(trimmed) : {
				typeParamNames: [],
				underlyingTypeText: null
			};
			final staticFields = scanResolvedTypeStaticFields(path, trimmed, kind);
			out.push({
				name: trimmed,
				kind: kind,
				metadata: MacroState.listAppliedTypeMetadata(fullTypePath(trimmed)),
				typeParamNames: semantics.typeParamNames,
				underlyingTypeText: semantics.underlyingTypeText,
				staticFields: staticFields,
				file: span.file,
				min: span.min,
				max: span.max
			});
		}

		final filtered = readFilteredResolvedModuleSource(path);
		if (filtered.length > 0) {
			for (c in ParserStageScanHelpers.scanModuleLocalHelperClasses(filtered, null))
				push("class", HxClassDecl.getName(c));
			for (c in ParserStageScanHelpers.scanModuleLocalHelperEnums(filtered, null))
				push("enum", HxClassDecl.getName(c));
			for (c in ParserStageScanHelpers.scanModuleLocalHelperTypedefs(filtered, null))
				push("typedef", HxClassDecl.getName(c));
			for (c in ParserStageScanHelpers.scanModuleLocalHelperAbstracts(filtered, null))
				push("abstract", HxClassDecl.getName(c));
		}

		final mainName = fallbackMainName == null ? "" : StringTools.trim(fallbackMainName);
		if (includeFallbackMain && mainName.length > 0) {
			final mainMetadata = MacroState.listAppliedTypeMetadata(fullTypePath(mainName));
			var existingIndex = -1;
			for (i in 0...out.length)
				if (out[i].name == mainName) {
					existingIndex = i;
					break;
				}
			if (existingIndex >= 0) {
				final existing = out.splice(existingIndex, 1)[0];
				out.unshift({
					name: existing.name,
					kind: existing.kind,
					metadata: mainMetadata,
					typeParamNames: existing.typeParamNames,
					underlyingTypeText: existing.underlyingTypeText,
					staticFields: existing.staticFields,
					file: existing.file,
					min: existing.min,
					max: existing.max
				});
			} else {
				out.unshift({
					name: mainName,
					kind: "class",
					metadata: mainMetadata,
					typeParamNames: [],
					underlyingTypeText: null,
					staticFields: scanResolvedTypeStaticFields(path, mainName, "class"),
					file: path,
					min: 0,
					max: 0
				});
			}
		}

		return out;
	}

	static function scanResolvedTypeSemantics(path:String):Map<String, RuntimeResolvedTypeSemantics> {
		final out = new Map<String, RuntimeResolvedTypeSemantics>();
		final source = readFilteredResolvedModuleSource(path);
		if (source.length == 0)
			return out;

		var braceDepth = 0;
		var i = 0;
		while (i < source.length) {
			final c = source.charCodeAt(i);
			if (c == "\"".code || c == "'".code) {
				i = skipQuotedText(source, i);
				continue;
			}
			if (c == "/".code && i + 1 < source.length) {
				final next = source.charCodeAt(i + 1);
				if (next == "/".code) {
					i = skipLineComment(source, i);
					continue;
				}
				if (next == "*".code) {
					i = skipBlockComment(source, i);
					continue;
				}
			}
			if (c == "{".code) {
				braceDepth++;
				i++;
				continue;
			}
			if (c == "}".code) {
				if (braceDepth > 0)
					braceDepth--;
				i++;
				continue;
			}
			if (braceDepth == 0) {
				if (hasKeywordAt(source, i, "typedef")) {
					final parsed = parseTypedefSemantics(source, i);
					if (parsed != null) {
						out.set(parsed.name, {
							typeParamNames: parsed.typeParamNames,
							underlyingTypeText: parsed.underlyingTypeText
						});
						i = parsed.nextIndex;
						continue;
					}
				}
				if (hasKeywordAt(source, i, "abstract")) {
					final prevWord = previousWord(source, i);
					if (prevWord != "enum") {
						final parsed = parseAbstractSemantics(source, i);
						if (parsed != null) {
							out.set(parsed.name, {
								typeParamNames: parsed.typeParamNames,
								underlyingTypeText: parsed.underlyingTypeText
							});
							i = parsed.nextIndex;
							continue;
						}
					}
				}
			}
			i++;
		}

		return out;
	}

	static function parseTypedefSemantics(source:String, start:Int):Null<{
		name:String,
		typeParamNames:Array<String>,
		underlyingTypeText:String,
		nextIndex:Int
	}> {
		var i = skipWhitespaceText(source, start + "typedef".length);
		final name = readIdent(source, i);
		if (name == null)
			return null;
		i += name.length;
		var typeParamNames = [];
		i = skipWhitespaceText(source, i);
		if (i < source.length && source.charCodeAt(i) == "<".code) {
			final angleEnd = scanBalancedText(source, i, "<".code, ">".code);
			if (angleEnd < 0)
				return null;
			typeParamNames = parseTypeParamNames(source.substr(i + 1, angleEnd - i - 2));
			i = angleEnd;
		}
		i = skipWhitespaceText(source, i);
		if (i >= source.length || source.charCodeAt(i) != "=".code)
			return null;
		final bodyStart = skipWhitespaceText(source, i + 1);
		final bodyEnd = scanTopLevelTypeTerminator(source, bodyStart, ";".code);
		if (bodyEnd < 0)
			return null;
		return {
			name: name,
			typeParamNames: typeParamNames,
			underlyingTypeText: StringTools.trim(source.substr(bodyStart, bodyEnd - bodyStart)),
			nextIndex: bodyEnd + 1
		};
	}

	static function parseAbstractSemantics(source:String, start:Int):Null<{
		name:String,
		typeParamNames:Array<String>,
		underlyingTypeText:String,
		nextIndex:Int
	}> {
		var i = skipWhitespaceText(source, start + "abstract".length);
		final name = readIdent(source, i);
		if (name == null)
			return null;
		i += name.length;
		var typeParamNames = [];
		i = skipWhitespaceText(source, i);
		if (i < source.length && source.charCodeAt(i) == "<".code) {
			final angleEnd = scanBalancedText(source, i, "<".code, ">".code);
			if (angleEnd < 0)
				return null;
			typeParamNames = parseTypeParamNames(source.substr(i + 1, angleEnd - i - 2));
			i = angleEnd;
		}
		i = skipWhitespaceText(source, i);
		if (i >= source.length || source.charCodeAt(i) != "(".code)
			return null;
		final parenEnd = scanBalancedText(source, i, "(".code, ")".code);
		if (parenEnd < 0)
			return null;
		return {
			name: name,
			typeParamNames: typeParamNames,
			underlyingTypeText: StringTools.trim(source.substr(i + 1, parenEnd - i - 2)),
			nextIndex: parenEnd
		};
	}

	static function parseTypeParamNames(source:String):Array<String> {
		final out = new Array<String>();
		for (part in splitTopLevelTypeParts(source, ",".code)) {
			final trimmed = StringTools.trim(part);
			if (trimmed.length == 0)
				continue;
			final name = readIdent(trimmed, 0);
			if (name != null && name.length > 0)
				out.push(name);
		}
		return out;
	}

	static function splitTopLevelTypeParts(source:String, separator:Int):Array<String> {
		final out = new Array<String>();
		var start = 0;
		var angleDepth = 0;
		var parenDepth = 0;
		var braceDepth = 0;
		var bracketDepth = 0;
		var i = 0;
		while (i < source.length) {
			final c = source.charCodeAt(i);
			if (c == "\"".code || c == "'".code) {
				i = skipQuotedText(source, i);
				continue;
			}
			switch (c) {
				case "<".code:
					angleDepth++;
				case ">".code:
					if (angleDepth > 0)
						angleDepth--;
				case "(".code:
					parenDepth++;
				case ")".code:
					if (parenDepth > 0)
						parenDepth--;
				case "{".code:
					braceDepth++;
				case "}".code:
					if (braceDepth > 0)
						braceDepth--;
				case "[".code:
					bracketDepth++;
				case "]".code:
					if (bracketDepth > 0)
						bracketDepth--;
				case _:
					if (c == separator && angleDepth == 0 && parenDepth == 0 && braceDepth == 0 && bracketDepth == 0) {
						out.push(source.substr(start, i - start));
						start = i + 1;
					}
			}
			i++;
		}
		out.push(source.substr(start));
		return out;
	}

	static function scanTopLevelTypeTerminator(source:String, start:Int, terminator:Int):Int {
		var angleDepth = 0;
		var parenDepth = 0;
		var braceDepth = 0;
		var bracketDepth = 0;
		var i = start;
		while (i < source.length) {
			final c = source.charCodeAt(i);
			if (c == "\"".code || c == "'".code) {
				i = skipQuotedText(source, i);
				continue;
			}
			switch (c) {
				case "<".code:
					angleDepth++;
				case ">".code:
					if (angleDepth > 0)
						angleDepth--;
				case "(".code:
					parenDepth++;
				case ")".code:
					if (parenDepth > 0)
						parenDepth--;
				case "{".code:
					braceDepth++;
				case "}".code:
					if (braceDepth > 0)
						braceDepth--;
				case "[".code:
					bracketDepth++;
				case "]".code:
					if (bracketDepth > 0)
						bracketDepth--;
				case _:
					if (c == terminator && angleDepth == 0 && parenDepth == 0 && braceDepth == 0 && bracketDepth == 0)
						return i;
			}
			i++;
		}
		return -1;
	}

	static function previousWord(source:String, index:Int):String {
		var i = index - 1;
		while (i >= 0) {
			final c = source.charCodeAt(i);
			if (c == " ".code || c == "\t".code || c == "\n".code || c == "\r".code)
				i--;
			else
				break;
		}
		if (i < 0)
			return "";
		var end = i + 1;
		while (i >= 0) {
			final c = source.charCodeAt(i);
			if (isIdentChar(c))
				i--;
			else
				break;
		}
		return source.substr(i + 1, end - i - 1);
	}

	static function readIdent(source:String, index:Int):Null<String> {
		if (index < 0 || index >= source.length)
			return null;
		final first = source.charCodeAt(index);
		final firstOk = first == "_".code || (first >= "A".code && first <= "Z".code) || (first >= "a".code && first <= "z".code);
		if (!firstOk)
			return null;
		var i = index + 1;
		while (i < source.length && isIdentChar(source.charCodeAt(i)))
			i++;
		return source.substr(index, i - index);
	}

	static function hasKeywordAt(source:String, index:Int, keyword:String):Bool {
		if (index < 0 || index + keyword.length > source.length)
			return false;
		if (source.substr(index, keyword.length) != keyword)
			return false;
		final beforeOk = index == 0 || !isIdentChar(source.charCodeAt(index - 1));
		final afterIndex = index + keyword.length;
		final afterOk = afterIndex >= source.length || !isIdentChar(source.charCodeAt(afterIndex));
		return beforeOk && afterOk;
	}

	static function isIdentChar(c:Int):Bool {
		return c == "_".code
			|| (c >= "A".code && c <= "Z".code)
			|| (c >= "a".code && c <= "z".code)
			|| (c >= "0".code && c <= "9".code);
	}

	static function skipWhitespaceText(source:String, index:Int):Int {
		var i = index;
		while (i < source.length) {
			final c = source.charCodeAt(i);
			if (c == " ".code || c == "\t".code || c == "\n".code || c == "\r".code)
				i++;
			else
				break;
		}
		return i;
	}

	static function scanBalancedText(source:String, start:Int, open:Int, close:Int):Int {
		if (start < 0 || start >= source.length || source.charCodeAt(start) != open)
			return -1;
		var depth = 0;
		var i = start;
		while (i < source.length) {
			final c = source.charCodeAt(i);
			if (c == "\"".code || c == "'".code) {
				i = skipQuotedText(source, i);
				continue;
			}
			if (c == open)
				depth++;
			else if (c == close) {
				depth--;
				if (depth == 0)
					return i + 1;
			}
			i++;
		}
		return -1;
	}

	static function skipQuotedText(source:String, start:Int):Int {
		final quote = source.charCodeAt(start);
		var i = start + 1;
		while (i < source.length) {
			final c = source.charCodeAt(i);
			if (c == "\\".code) {
				i += 2;
				continue;
			}
			if (c == quote)
				return i + 1;
			i++;
		}
		return source.length;
	}

	static function skipLineComment(source:String, start:Int):Int {
		var i = start;
		while (i < source.length) {
			final c = source.charCodeAt(i);
			i++;
			if (c == "\n".code)
				break;
		}
		return i;
	}

	static function skipBlockComment(source:String, start:Int):Int {
		var i = start + 2;
		while (i < source.length - 1) {
			if (source.charCodeAt(i) == "*".code && source.charCodeAt(i + 1) == "/".code)
				return i + 2;
			i++;
		}
		return source.length;
	}

	static function scanResolvedModuleTypeSpans(path:String):Map<String, {file:String, min:Int, max:Int}> {
		final out = new Map<String, {file:String, min:Int, max:Int}>();
		final filtered = readFilteredResolvedModuleSource(path);
		if (filtered.length == 0)
			return out;

		var braceDepth = 0;
		var blockCommentDepth = 0;
		var lineOffset = 0;
		final lines = splitLinesPreserveNewlines(filtered);

		function countChar(text:String, ch:String):Int {
			var count = 0;
			var i = 0;
			while (i < text.length) {
				if (text.charAt(i) == ch)
					count += 1;
				i += 1;
			}
			return count;
		}

		function stripLeadingTypeMetadata(text:String):String {
			var outText = text;
			while (true) {
				final trimmed = StringTools.ltrim(outText);
				if (!StringTools.startsWith(trimmed, "@:"))
					return trimmed;
				var i = 2;
				var depth = 0;
				while (i < trimmed.length) {
					final ch = trimmed.charAt(i);
					switch (ch) {
						case "(":
							depth += 1;
						case ")":
							if (depth > 0)
								depth -= 1;
						case " " | "\t":
							if (depth == 0) {
								outText = trimmed.substr(i + 1);
								i = trimmed.length;
							}
						case _:
					}
					i += 1;
				}
				if (i >= trimmed.length)
					return trimmed;
			}
			return outText;
		}

		function lineSpan(rawLine:String, start:Int):{min:Int, max:Int} {
			var min = 0;
			while (min < rawLine.length) {
				final c = rawLine.charCodeAt(min);
				if (c == " ".code || c == "\t".code)
					min += 1;
				else
					break;
			}
			var max = rawLine.length;
			while (max > min) {
				final c = rawLine.charCodeAt(max - 1);
				if (c == "\n".code || c == "\r".code)
					max -= 1;
				else
					break;
			}
			return {
				min: start + min,
				max: start + max
			};
		}

		function record(name:String, span:{min:Int, max:Int}):Void {
			final trimmed = name == null ? "" : StringTools.trim(name);
			if (trimmed.length == 0 || out.exists(trimmed))
				return;
			out.set(trimmed, {
				file: path,
				min: span.min,
				max: span.max
			});
		}

		for (rawLine in lines) {
			final currentLineOffset = lineOffset;
			lineOffset += rawLine.length;
			var line = rawLine;
			if (blockCommentDepth > 0) {
				while (line.length > 0 && blockCommentDepth > 0) {
					final close = line.indexOf("*/");
					if (close == -1) {
						line = "";
					} else {
						blockCommentDepth -= 1;
						line = line.substr(close + 2);
					}
				}
			}
			while (true) {
				final open = line.indexOf("/*");
				if (open == -1)
					break;
				final close = line.indexOf("*/", open + 2);
				if (close == -1) {
					blockCommentDepth += 1;
					line = line.substr(0, open);
					break;
				}
				line = line.substr(0, open) + line.substr(close + 2);
			}
			line = {
				var text = line;
				var inString = false;
				var quote = "";
				var i = 0;
				while (i < text.length - 1) {
					final ch = text.charAt(i);
					if (inString) {
						if (ch == "\\") {
							i += 2;
							continue;
						}
						if (ch == quote)
							inString = false;
						i += 1;
						continue;
					}
					if (ch == "\"" || ch == "'") {
						inString = true;
						quote = ch;
						i += 1;
						continue;
					}
					if (ch == "/" && text.charAt(i + 1) == "/") {
						text = text.substr(0, i);
						break;
					}
					i += 1;
				}
				text;
			};
			final trimmed = stripLeadingTypeMetadata(StringTools.trim(line));
			if (trimmed.length == 0) {
				braceDepth += countChar(line, "{");
				braceDepth -= countChar(line, "}");
				if (braceDepth < 0)
					braceDepth = 0;
				continue;
			}
			if (braceDepth == 0) {
				final span = lineSpan(rawLine, currentLineOffset);
				final enumAbstract = ~/^(?:private\s+|extern\s+|final\s+)?enum\s+abstract\s+([A-Za-z_][A-Za-z0-9_]*)/;
				final classDecl = ~/^(?:private\s+|extern\s+|final\s+)?class\s+([A-Za-z_][A-Za-z0-9_]*)/;
				final enumDecl = ~/^(?:private\s+|extern\s+|final\s+)?enum\s+([A-Za-z_][A-Za-z0-9_]*)/;
				final typedefDecl = ~/^(?:private\s+|extern\s+|final\s+)?typedef\s+([A-Za-z_][A-Za-z0-9_]*)/;
				final abstractDecl = ~/^(?:private\s+|extern\s+|final\s+)?abstract\s+([A-Za-z_][A-Za-z0-9_]*)/;
				if (enumAbstract.match(trimmed))
					record(enumAbstract.matched(1), span);
				else if (classDecl.match(trimmed))
					record(classDecl.matched(1), span);
				else if (enumDecl.match(trimmed))
					record(enumDecl.matched(1), span);
				else if (typedefDecl.match(trimmed))
					record(typedefDecl.matched(1), span);
				else if (abstractDecl.match(trimmed))
					record(abstractDecl.matched(1), span);
			}
			braceDepth += countChar(line, "{");
			braceDepth -= countChar(line, "}");
			if (braceDepth < 0)
				braceDepth = 0;
		}

		return out;
	}

	/**
		Scan a narrow top-level module-field subset from filtered source.

		Why
		- Some real macro consumers fall back to `Context.getModule(...)` specifically to inspect a
		  synthetic `KModuleFields(module)` carrier and metadata on its static fields.
		- The external-host runtime already preserves top-level type declarations, but without a
		  module-field carrier those consumers still see an incomplete module model.

		What
		- Detects top-level declarations at brace depth zero after `#if` filtering:
		  - metadata lines (`@:meta`, `@:meta(args)`)
		  - `function foo(...)`
		  - `var foo`
		  - `final foo`
		- Carries a narrow initializer-text snapshot for `var` / `final` declarations when the
		  initializer is present on the declaration line.
		- Carries a narrow function-signature snapshot for top-level `function` declarations:
		  - arg names
		  - `opt` flags
		  - arg type text
		  - return type text

		Gotchas
		- This is intentionally narrower than full parser fidelity.
		- Initializer capture is still a one-line subset; unsupported or multiline initializers are
		  left empty and the runtime carrier falls back to `expr() == null` / `Dynamic`.
		- Function bodies are not carried; runtime module-field carriers still expose `expr() == null`
		  for methods and rely on `field.type` for the useful signature path.
	**/
	public static function scanResolvedModuleFields(path:String):Array<RuntimeResolvedModuleFieldSnapshot> {
		final out = new Array<RuntimeResolvedModuleFieldSnapshot>();
		final filtered = readFilteredResolvedModuleSource(path);
		if (filtered.length == 0)
			return out;

		var braceDepth = 0;
		var blockCommentDepth = 0;
		var pendingMetadata = new Array<String>();
		var lineOffset = 0;
		final seen = new Map<String, Bool>();
		final lines = splitLinesPreserveNewlines(filtered);

		function countChar(text:String, ch:String):Int {
			var count = 0;
			var i = 0;
			while (i < text.length) {
				if (text.charAt(i) == ch)
					count += 1;
				i += 1;
			}
			return count;
		}

		function stripLineComments(text:String):String {
			var inString = false;
			var quote = "";
			var i = 0;
			while (i < text.length - 1) {
				final ch = text.charAt(i);
				if (inString) {
					if (ch == "\\") {
						i += 2;
						continue;
					}
					if (ch == quote)
						inString = false;
					i += 1;
					continue;
				}
				if (ch == "\"" || ch == "'") {
					inString = true;
					quote = ch;
					i += 1;
					continue;
				}
				if (ch == "/" && text.charAt(i + 1) == "/")
					return text.substr(0, i);
				i += 1;
			}
			return text;
		}

		function extractName(prefix:String, keyword:String):String {
			final rest = StringTools.trim(prefix.substr(keyword.length));
			if (rest.length == 0)
				return "";
			final match = ~/^([A-Za-z_][A-Za-z0-9_]*)/;
			return match.match(rest) ? match.matched(1) : "";
		}

		function extractInitializer(prefix:String, keyword:String):Null<String> {
			final rest = StringTools.trim(prefix.substr(keyword.length));
			if (rest.length == 0)
				return null;
			final nameMatch = ~/^([A-Za-z_][A-Za-z0-9_]*)/;
			if (!nameMatch.match(rest))
				return null;
			final afterName = StringTools.trim(rest.substr(nameMatch.matchedPos().pos + nameMatch.matchedPos().len));
			if (afterName.length == 0)
				return null;
			final eqIndex = afterName.indexOf("=");
			if (eqIndex < 0)
				return null;
			var exprText = StringTools.trim(afterName.substr(eqIndex + 1));
			if (exprText.length == 0)
				return null;
			if (StringTools.endsWith(exprText, ";"))
				exprText = StringTools.trim(exprText.substr(0, exprText.length - 1));
			return exprText.length == 0 ? null : exprText;
		}

		function splitTopLevelComma(text:String):Array<String> {
			final out = new Array<String>();
			if (text == null)
				return out;
			var start = 0;
			var parenDepth = 0;
			var bracketDepth = 0;
			var braceDepth = 0;
			var angleDepth = 0;
			var inString = false;
			var quote = "";
			var i = 0;
			while (i < text.length) {
				final ch = text.charAt(i);
				if (inString) {
					if (ch == "\\") {
						i += 2;
						continue;
					}
					if (ch == quote)
						inString = false;
					i += 1;
					continue;
				}
				switch (ch) {
					case "\"" | "'":
						inString = true;
						quote = ch;
					case "(":
						parenDepth += 1;
					case ")":
						if (parenDepth > 0)
							parenDepth -= 1;
					case "[":
						bracketDepth += 1;
					case "]":
						if (bracketDepth > 0)
							bracketDepth -= 1;
					case "{":
						braceDepth += 1;
					case "}":
						if (braceDepth > 0)
							braceDepth -= 1;
					case "<":
						angleDepth += 1;
					case ">":
						if (angleDepth > 0)
							angleDepth -= 1;
					case ",":
						if (parenDepth == 0 && bracketDepth == 0 && braceDepth == 0 && angleDepth == 0) {
							out.push(text.substr(start, i - start));
							start = i + 1;
						}
					case _:
				}
				i += 1;
			}
			out.push(text.substr(start));
			return out;
		}

		function parseFunctionArgs(text:String):Array<{name:String, opt:Bool, typeText:String}> {
			final out = new Array<{name:String, opt:Bool, typeText:String}>();
			for (segment in splitTopLevelComma(text)) {
				final trimmed = StringTools.trim(segment);
				if (trimmed.length == 0)
					continue;
				var working = trimmed;
				var optional = false;
				if (StringTools.startsWith(working, "?")) {
					optional = true;
					working = StringTools.trim(working.substr(1));
				}
				final nameMatch = ~/^([A-Za-z_][A-Za-z0-9_]*)/;
				if (!nameMatch.match(working))
					continue;
				final name = nameMatch.matched(1);
				var afterName = StringTools.trim(working.substr(nameMatch.matchedPos().pos + nameMatch.matchedPos().len));
				var typeText = "Dynamic";
				final eqIndex = afterName.indexOf("=");
				if (eqIndex >= 0) {
					optional = true;
					afterName = StringTools.trim(afterName.substr(0, eqIndex));
				}
				if (StringTools.startsWith(afterName, ":")) {
					final parsedType = StringTools.trim(afterName.substr(1));
					if (parsedType.length > 0)
						typeText = parsedType;
				}
				out.push({
					name: name,
					opt: optional,
					typeText: typeText
				});
			}
			return out;
		}

		function parseFunctionSignature(prefix:String):{
			args:Array<{name:String, opt:Bool, typeText:String}>,
			returnTypeText:Null<String>
		} {
			final signature = StringTools.trim(prefix.substr("function".length));
			final openParen = signature.indexOf("(");
			final closeParen = signature.lastIndexOf(")");
			if (openParen < 0 || closeParen < openParen)
				return {
					args: [],
					returnTypeText: null
				};
			final argsText = signature.substr(openParen + 1, closeParen - openParen - 1);
			var tail = StringTools.trim(signature.substr(closeParen + 1));
			var returnTypeText:Null<String> = null;
			if (StringTools.startsWith(tail, ":")) {
				tail = StringTools.trim(tail.substr(1));
				final braceIndex = tail.indexOf("{");
				if (braceIndex >= 0)
					tail = StringTools.trim(tail.substr(0, braceIndex));
				if (StringTools.endsWith(tail, ";"))
					tail = StringTools.trim(tail.substr(0, tail.length - 1));
				if (tail.length > 0)
					returnTypeText = tail;
			}
			return {
				args: parseFunctionArgs(argsText),
				returnTypeText: returnTypeText
			};
		}

		function lineSpan(rawLine:String, start:Int):{min:Int, max:Int} {
			var min = 0;
			while (min < rawLine.length) {
				final c = rawLine.charCodeAt(min);
				if (c == " ".code || c == "\t".code)
					min += 1;
				else
					break;
			}
			var max = rawLine.length;
			while (max > min) {
				final c = rawLine.charCodeAt(max - 1);
				if (c == "\n".code || c == "\r".code)
					max -= 1;
				else
					break;
			}
			return {
				min: start + min,
				max: start + max
			};
		}

		function push(kind:String, name:String, span:{min:Int, max:Int}, ?initExpr:Null<String>, ?args:Array<{name:String, opt:Bool, typeText:String}>,
				?returnTypeText:Null<String>):Void {
			final trimmed = StringTools.trim(name == null ? "" : name);
			if (trimmed.length == 0 || seen.exists(trimmed))
				return;
			seen.set(trimmed, true);
			out.push({
				name: trimmed,
				kind: kind,
				metadata: pendingMetadata.copy(),
				initExpr: initExpr,
				args: args == null ? [] : args.copy(),
				returnTypeText: returnTypeText,
				file: path,
				min: span.min,
				max: span.max
			});
			pendingMetadata = [];
		}

		for (rawLine in lines) {
			final currentLineOffset = lineOffset;
			lineOffset += rawLine.length;
			var line = rawLine;
			if (blockCommentDepth > 0) {
				while (line.length > 0 && blockCommentDepth > 0) {
					final close = line.indexOf("*/");
					if (close == -1) {
						line = "";
					} else {
						blockCommentDepth -= 1;
						line = line.substr(close + 2);
					}
				}
			}

			while (true) {
				final open = line.indexOf("/*");
				if (open == -1)
					break;
				final close = line.indexOf("*/", open + 2);
				if (close == -1) {
					blockCommentDepth += 1;
					line = line.substr(0, open);
					break;
				}
				line = line.substr(0, open) + line.substr(close + 2);
			}

			line = stripLineComments(line);
			final trimmed = StringTools.trim(line);
			if (trimmed.length == 0)
				continue;

			if (braceDepth == 0) {
				final span = lineSpan(rawLine, currentLineOffset);
				if (StringTools.startsWith(trimmed, "@:")) {
					pendingMetadata.push(trimmed);
				} else if (StringTools.startsWith(trimmed, "function ")) {
					final parsed = parseFunctionSignature(trimmed);
					push("method", extractName(trimmed, "function"), span, null, parsed.args, parsed.returnTypeText);
				} else if (StringTools.startsWith(trimmed, "var ")) {
					push("var", extractName(trimmed, "var"), span, extractInitializer(trimmed, "var"));
				} else if (StringTools.startsWith(trimmed, "final ")) {
					push("final", extractName(trimmed, "final"), span, extractInitializer(trimmed, "final"));
				} else if (!StringTools.startsWith(trimmed, "package ")
					&& !StringTools.startsWith(trimmed, "import ")
					&& !StringTools.startsWith(trimmed, "using ")
					&& !StringTools.startsWith(trimmed, "#if")
					&& !StringTools.startsWith(trimmed, "#elseif")
					&& !StringTools.startsWith(trimmed, "#else")
					&& !StringTools.startsWith(trimmed, "#end")) {
					pendingMetadata = [];
				}
			}

			braceDepth += countChar(line, "{");
			braceDepth -= countChar(line, "}");
			if (braceDepth < 0)
				braceDepth = 0;
		}

		return out;
	}

	static function connect():MacroClient {
		final exe = resolveMacroHostExe();
		if (exe == null || exe.length == 0) {
			throw "missing macro host exe (set HXHX_MACRO_HOST_EXE)";
		}
		return MacroClient.connect(exe);
	}
}

/**
	One macro-host client session (one process).

	Why
	- The Stage 4 Model A transport is line-based and stateful: the server prints a banner,
	  then expects a hello handshake, and then serves requests until `quit`.
	- Keeping a dedicated session type makes it easy to evolve toward:
	  - batching,
	  - request IDs,
	  - macro server reuse / caching.

	How
	- Uses `sys.io.Process`, which is implemented for the OCaml target via a small runtime shim
	  (`std/runtime/HxProcess.ml`) and the override in `std/_std/sys/io/Process.hx`.
**/
private class MacroClient {
	final proc:sys.io.Process;
	final hostIdleTimeoutSecs:Int;
	final hostTotalTimeoutSecs:Int;
	var nextId:Int = 1;
	var timeoutTriggered:Bool = false;

	static final TRACE:Bool = {
		final v = Sys.getEnv("HXHX_MACRO_TRACE");
		v == "1"
		|| v == "true"
		|| v == "yes";
	};
	static final TRACE_HOST:Bool = {
		final v = Sys.getEnv("HXHX_MACRO_HOST_TRACE");
		v == "1"
		|| v == "true"
		|| v == "yes";
	};
	static inline var HOST_POLL_INTERVAL_SECS:Float = 0.05;

	function new(proc:sys.io.Process) {
		this.proc = proc;
		this.hostIdleTimeoutSecs = parseTimeoutSeconds("HXHX_MACRO_HOST_IDLE_SECS", 90);
		this.hostTotalTimeoutSecs = parseTimeoutSeconds("HXHX_MACRO_HOST_TOTAL_SECS", 300);
	}

	public static function connect(exe:String):MacroClient {
		final p = new sys.io.Process(exe, []);
		final banner = p.stdout.readLine();
		if (banner != "hxhx_macro_rpc_v=1") {
			p.close();
			throw "macro host: unsupported banner: " + banner;
		}
		p.stdin.writeString("hello proto=1\n", null);
		p.stdin.flush();
		final ok = p.stdout.readLine();
		if (ok != "ok") {
			p.close();
			throw "macro host: handshake failed: " + ok;
		}
		return new MacroClient(p);
	}

	public function call(method:String, tail:String):String {
		final id = nextId++;
		final callStart = haxe.Timer.stamp();
		var lastProgress = callStart;
		if (TRACE) {
			try
				Sys.stderr().writeString("[hxhx macro rpc] -> " + method + "\n")
			catch (_:haxe.io.Error) {} catch (_:String) {}
		}
		final msg = tail == null
			|| tail.length == 0 ? ("req " + id + " " + method + "\n") : ("req " + id + " " + method + " " + tail + "\n");
		try {
			proc.stdin.writeString(msg, null);
			proc.stdin.flush();
		} catch (e:haxe.io.Error) {
			throw "macro host: failed to write request: " + Std.string(e);
		} catch (e:String) {
			throw "macro host: failed to write request: " + e;
		}

		while (true) {
			final line = readLineForPhase(method, "response", callStart, lastProgress);
			lastProgress = haxe.Timer.stamp();
			final trimmed = StringTools.trim(line);
			if (trimmed.length == 0)
				continue;

			// Duplex bring-up: while we are waiting for a response, the macro host may send its own request
			// back to the compiler (this process).
			if (StringTools.startsWith(trimmed, "req ")) {
				handleInboundReq(trimmed);
				continue;
			}

			final parts = MacroProtocol.splitN(trimmed, 3);
			final rid = Std.parseInt(parts[1]);
			if (rid == null || rid != id)
				throw "macro host: response id mismatch: " + trimmed;
			final status = parts[2];
			final respTail = parts[3];
			if (status == "ok")
				return MacroProtocol.kvGet(respTail, "v");

			final msg = MacroProtocol.kvGet(respTail, "m");
			final pos = MacroProtocol.kvGet(respTail, "p");
			throw(pos != null && pos.length > 0) ? ("macro host: " + msg + " (" + pos + ")") : ("macro host: " + msg);
		}

		return "";
	}

	static function parseTimeoutSeconds(name:String, defaultValue:Int):Int {
		final raw = Sys.getEnv(name);
		if (raw == null)
			return defaultValue;
		final text = StringTools.trim(raw);
		if (text.length == 0)
			return defaultValue;
		final parsed = Std.parseInt(text);
		if (parsed == null || parsed < 0) {
			try
				Sys.stderr().writeString('hxhx: invalid ${name}=${raw}; expected non-negative integer, using ${defaultValue}.\n')
			catch (_:haxe.io.Error) {} catch (_:String) {}
			return defaultValue;
		}
		return parsed;
	}

	function readLineForPhase(method:String, phase:String, callStart:Float, lastProgress:Float):String {
		final lineResult = readLineWithTimeout(method, phase, callStart, lastProgress);
		return switch (lineResult) {
			case ReadLine(line):
				line;
			case ReadEof:
				final hostStderr = drainStderr(60);
				final exitCode = try proc.exitCode() catch (_:String) -1;
				throw "macro host: unexpected EOF during "
					+ phase
					+ " (method="
					+ method
					+ ", exit="
					+ exitCode
					+ ")"
					+ (hostStderr.length == 0 ? "" : ("\nmacro host stderr:\n" + hostStderr));
			case ReadError(message):
				throw "macro host: failed to read " + phase + " line: " + message;
		}
	}

	function readLineWithTimeout(method:String, phase:String, callStart:Float, lastProgress:Float):MacroHostReadResult {
		#if eval
		try {
			return ReadLine(proc.stdout.readLine());
		} catch (_:haxe.io.Eof) {
			return ReadEof;
		} catch (e:haxe.io.Error) {
			return ReadError(Std.string(e));
		} catch (e:String) {
			return ReadError(e);
		}
		#else
		var result:MacroHostReadResult = ReadError("uninitialized");
		var done = false;
		sys.thread.Thread.create(function() {
			try {
				result = ReadLine(proc.stdout.readLine());
			} catch (_:haxe.io.Eof) {
				result = ReadEof;
			} catch (e:haxe.io.Error) {
				result = ReadError(Std.string(e));
			} catch (e:String) {
				result = ReadError(e);
			}
			done = true;
		});
		while (!done) {
			ensureNoTimeout(method, phase, callStart, lastProgress);
			Sys.sleep(HOST_POLL_INTERVAL_SECS);
		}
		return result;
		#end
	}

	function ensureNoTimeout(method:String, phase:String, callStart:Float, lastProgress:Float):Void {
		final now = haxe.Timer.stamp();
		final totalElapsed = now - callStart;
		final idleElapsed = now - lastProgress;

		if (hostTotalTimeoutSecs > 0 && totalElapsed >= hostTotalTimeoutSecs) {
			failTimeout("total", method, phase, totalElapsed, idleElapsed);
		}

		if (hostIdleTimeoutSecs > 0 && idleElapsed >= hostIdleTimeoutSecs) {
			failTimeout("idle", method, phase, totalElapsed, idleElapsed);
		}
	}

	function failTimeout(reason:String, method:String, phase:String, totalElapsed:Float, idleElapsed:Float):Void {
		timeoutTriggered = true;
		final marker = "MACRO_HOST_STALL_DETECTED=1" + " reason=" + reason + " method=" + method + " phase=" + phase;
		try
			Sys.stderr().writeString(marker + "\n")
		catch (_:haxe.io.Error) {} catch (_:String) {}

		#if !eval
		sys.thread.Thread.create(function() {
			try
				proc.kill()
			catch (_:haxe.io.Error) {} catch (_:String) {}
			try
				proc.close()
			catch (_:haxe.io.Error) {} catch (_:String) {}
		});
		#end

		throw "macro host timeout (reason=" + reason + ", method=" + method + ", phase=" + phase + ", total=" + Std.int(totalElapsed) + "s, idle="
			+ Std.int(idleElapsed) + "s)\n" + marker;
	}

	function drainStderr(maxLines:Int):String {
		if (maxLines <= 0)
			return "";
		final lines = new Array<String>();
		try {
			while (lines.length < maxLines) {
				lines.push(proc.stderr.readLine());
			}
		} catch (_:haxe.io.Eof) {
			// ok
		} catch (_:haxe.io.Error) {} catch (_:String) {}
		return lines.join("\n");
	}

	function handleInboundReq(line:String):Void {
		final parts = MacroProtocol.splitN(line, 3); // ["req", id, method, tail]
		final id = Std.parseInt(parts[1]);
		final method = parts[2];
		final tail = parts[3];
		if (TRACE) {
			try
				Sys.stderr().writeString("[hxhx macro rpc] <- " + method + "\n")
			catch (_:haxe.io.Error) {} catch (_:String) {}
		}
		if (id == null) {
			replyErr(0, "missing id");
			return;
		}

		try {
			switch (method) {
				case "compiler.define":
					final name = MacroProtocol.kvGet(tail, "n");
					final value = MacroProtocol.kvGet(tail, "v");
					if (name == null || name.length == 0) {
						replyErr(id, method + ": missing name");
						return;
					}
					MacroState.setDefine(name, value);
					replyOk(id, MacroProtocol.encodeLen("v", "ok"));
				case "compiler.getDefine":
					final name = MacroProtocol.kvGet(tail, "n");
					if (name == null || name.length == 0) {
						replyErr(id, method + ": missing name");
						return;
					}
					final payload = MacroProtocol.encodeLen("d", MacroState.defined(name) ? "1" : "0")
						+ " "
						+ MacroProtocol.encodeLen("v", MacroState.definedValue(name));
					replyOk(id, MacroProtocol.encodeLen("v", payload));
				case "compiler.getConfiguration":
					final config = MacroState.getCompilerConfigurationSnapshot();
					final parts = new Array<String>();
					parts.push(MacroProtocol.encodeLen("ver", Std.string(config.version)));
					parts.push(MacroProtocol.encodeLen("dbg", config.debug ? "1" : "0"));
					parts.push(MacroProtocol.encodeLen("vrb", config.verbose ? "1" : "0"));
					parts.push(MacroProtocol.encodeLen("opt", config.foptimize ? "1" : "0"));
					parts.push(MacroProtocol.encodeLen("uni", config.supportsUnicode ? "1" : "0"));
					parts.push(MacroProtocol.encodeLen("target", config.targetName));
					parts.push(MacroProtocol.encodeLen("ac", Std.string(config.args.length)));
					for (i in 0...config.args.length)
						parts.push(MacroProtocol.encodeLen("a" + i, config.args[i]));
					parts.push(MacroProtocol.encodeLen("sc", Std.string(config.stdPath.length)));
					for (i in 0...config.stdPath.length)
						parts.push(MacroProtocol.encodeLen("s" + i, config.stdPath[i]));
					replyOk(id, MacroProtocol.encodeLen("v", parts.join(" ")));
				case "compiler.registerHook":
					final kind = MacroProtocol.kvGet(tail, "k");
					final idStr = MacroProtocol.kvGet(tail, "i");
					final hid = Std.parseInt(idStr);
					if (kind == null || kind.length == 0) {
						replyErr(id, method + ": missing kind");
						return;
					}
					if (hid == null) {
						replyErr(id, method + ": invalid hook id");
						return;
					}
					MacroState.registerHook(kind, hid);
					replyOk(id, MacroProtocol.encodeLen("v", "ok"));
				case "compiler.emitOcamlModule":
					final name = MacroProtocol.kvGet(tail, "n");
					final source = MacroProtocol.kvGet(tail, "s");
					if (name == null || name.length == 0) {
						replyErr(id, method + ": missing module name");
						return;
					}
					MacroState.emitOcamlModule(name, source);
					replyOk(id, MacroProtocol.encodeLen("v", "ok"));
				case "compiler.addClassPath":
					final cp = MacroProtocol.kvGet(tail, "cp");
					if (cp == null || cp.length == 0) {
						replyErr(id, method + ": missing classpath");
						return;
					}
					MacroState.addClassPath(cp);
					replyOk(id, MacroProtocol.encodeLen("v", "ok"));
				case "compiler.includeModule":
					final modulePath = MacroProtocol.kvGet(tail, "m");
					if (modulePath == null || modulePath.length == 0) {
						replyErr(id, method + ": missing module path");
						return;
					}
					MacroState.includeModule(modulePath);
					replyOk(id, MacroProtocol.encodeLen("v", "ok"));
				case "compiler.addGlobalMetadata":
					final pathFilter = MacroProtocol.kvGet(tail, "p");
					final metadata = MacroProtocol.kvGet(tail, "m");
					final recursive = MacroProtocol.kvGet(tail, "r") == "1";
					final toTypes = MacroProtocol.kvGet(tail, "t") != "0";
					final toFields = MacroProtocol.kvGet(tail, "f") == "1";
					MacroState.registerGlobalMetadata(pathFilter, metadata, recursive, toTypes, toFields);
					replyOk(id, MacroProtocol.encodeLen("v", "ok"));
				case "compiler.registerCustomMetadata":
					final metadata = MacroProtocol.kvGet(tail, "m");
					final doc = MacroProtocol.kvGet(tail, "d");
					final source = MacroProtocol.kvGet(tail, "s");
					MacroState.registerCustomMetadata(metadata, doc, source);
					replyOk(id, MacroProtocol.encodeLen("v", "ok"));
				case "compiler.listAppliedTypeMetadata":
					final typePath = MacroProtocol.kvGet(tail, "p");
					final metadata = MacroState.listAppliedTypeMetadata(typePath);
					final parts = new Array<String>();
					parts.push(MacroProtocol.encodeLen("c", Std.string(metadata.length)));
					for (i in 0...metadata.length)
						parts.push(MacroProtocol.encodeLen("m" + i, metadata[i]));
					replyOk(id, MacroProtocol.encodeLen("v", parts.join(" ")));
				case "compiler.emitHxModule":
					final name = MacroProtocol.kvGet(tail, "n");
					final source = MacroProtocol.kvGet(tail, "s");
					if (name == null || name.length == 0) {
						replyErr(id, method + ": missing module name");
						return;
					}
					MacroState.emitHxModule(name, source);
					replyOk(id, MacroProtocol.encodeLen("v", "ok"));
				case "compiler.emitBuildFields":
					final modulePath = MacroProtocol.kvGet(tail, "m");
					final source = MacroProtocol.kvGet(tail, "s");
					if (modulePath == null || modulePath.length == 0) {
						replyErr(id, method + ": missing module path");
						return;
					}
					MacroState.emitBuildFields(modulePath, source);
					replyOk(id, MacroProtocol.encodeLen("v", "ok"));
				case "context.addResource":
					final name = MacroProtocol.kvGet(tail, "n");
					final hex = MacroProtocol.kvGet(tail, "d");
					if (name == null || name.length == 0) {
						replyErr(id, method + ": missing resource name");
						return;
					}
					if (hex == null || (hex.length & 1) != 0) {
						replyErr(id, method + ": invalid resource payload");
						return;
					}
					MacroState.addResource(name, haxe.io.Bytes.ofHex(hex));
					replyOk(id, MacroProtocol.encodeLen("v", "ok"));
				case "context.addMessage":
					final kind = MacroProtocol.kvGet(tail, "k");
					final msg = MacroProtocol.kvGet(tail, "m");
					final file = MacroProtocol.kvGet(tail, "f");
					final minRaw = MacroProtocol.kvGet(tail, "mi");
					final maxRaw = MacroProtocol.kvGet(tail, "ma");
					final min = Std.parseInt(minRaw);
					final max = Std.parseInt(maxRaw);
					MacroState.addMessage(kind, msg, {
						file: file == null || file.length == 0 ? "<macro>" : file,
						min: min == null || min < 0 ? 0 : min,
						max: max == null || max < 0 ? 0 : max});
					replyOk(id, MacroProtocol.encodeLen("v", "ok"));
				case "context.defined":
					final name = MacroProtocol.kvGet(tail, "n");
					replyOk(id, MacroProtocol.encodeLen("v", MacroState.defined(name) ? "1" : "0"));
				case "context.definedValue":
					final name = MacroProtocol.kvGet(tail, "n");
					replyOk(id, MacroProtocol.encodeLen("v", MacroState.definedValue(name)));
				case "context.currentPos":
					final pos = MacroState.getCurrentPos();
					final payload = MacroProtocol.encodeLen("f", pos.file) + " " + MacroProtocol.encodeLen("mi", Std.string(pos.min)) + " "
						+ MacroProtocol.encodeLen("ma", Std.string(pos.max));
					replyOk(id, MacroProtocol.encodeLen("v", payload));
				case "context.getExpectedType":
					replyOk(id, MacroProtocol.encodeLen("v", optionalText(MacroState.getExpectedTypeText())));
				case "context.getCallArguments":
					replyOk(id, MacroProtocol.encodeLen("v", encodeCallArgumentsPayload()));
				case "context.getMainExpr":
					replyOk(id, MacroProtocol.encodeLen("v", optionalText(MacroState.getMainExprText())));
				case "context.registerModuleDependency":
					final modulePath = MacroProtocol.kvGet(tail, "m");
					final externFile = MacroProtocol.kvGet(tail, "f");
					MacroState.registerModuleDependency(modulePath, externFile);
					replyOk(id, "");
				case "context.getLocalModule":
					replyOk(id, MacroProtocol.encodeLen("v", MacroState.getLocalModule()));
				case "context.getLocalType":
					replyOk(id, MacroProtocol.encodeLen("v", optionalText(MacroState.getLocalTypeText())));
				case "context.getLocalMethod":
					replyOk(id, MacroProtocol.encodeLen("v", optionalText(MacroState.getLocalMethod())));
				case "context.getLocalUsing":
					replyOk(id, MacroProtocol.encodeLen("v", encodeLocalUsingsPayload()));
				case "context.getLocalImports":
					replyOk(id, MacroProtocol.encodeLen("v", encodeLocalImportsPayload()));
				case "context.getLocalTVars":
					replyOk(id, MacroProtocol.encodeLen("v", encodeLocalTVarsPayload()));
				case "context.getType":
					final name = MacroProtocol.kvGet(tail, "n");
					if (name == null || name.length == 0) {
						replyErr(id, method + ": missing type name");
						return;
					}
					final classPaths = MacroState.listClassPaths();
					final cfg = MacroState.getCompilerConfigurationSnapshot();
					for (cp in cfg.stdPath)
						if (classPaths.indexOf(cp) == -1)
							classPaths.push(cp);
					final resolved = hxhx.Stage1Compiler.Stage1Resolver.resolveModule(classPaths, name, Sys.getCwd());
					if (resolved == null) {
						replyOk(id, MacroProtocol.encodeLen("v", ""));
						return;
					}
					final resolvedTypes = MacroHostClient.scanResolvedModuleTypes(name, resolved.path, resolved.className);
					final targetTypeName = {
						final parts = name.split(".");
						parts.length == 0 ? name : parts[parts.length - 1];
					}
					var kind = "class";
					var metadata = MacroState.listAppliedTypeMetadata(name);
					for (entry in resolvedTypes)
						if (entry.name == targetTypeName) {
							kind = entry.kind;
							metadata = entry.metadata;
							break;
						}
					final parts = new Array<String>();
					parts.push(MacroProtocol.encodeLen("ok", "1"));
					parts.push(MacroProtocol.encodeLen("t", name));
					parts.push(MacroProtocol.encodeLen("m", resolved.className));
					parts.push(MacroProtocol.encodeLen("k", kind));
					parts.push(MacroProtocol.encodeLen("f", {
						var file = resolved.path;
						for (entry in resolvedTypes)
							if (entry.name == targetTypeName) {
								file = entry.file;
								break;
							}
						file;
					}));
					parts.push(MacroProtocol.encodeLen("min", Std.string({
						var value = 0;
						for (entry in resolvedTypes)
							if (entry.name == targetTypeName) {
								value = entry.min;
								break;
							}
						value;
					})));
					parts.push(MacroProtocol.encodeLen("max", Std.string({
						var value = 0;
						for (entry in resolvedTypes)
							if (entry.name == targetTypeName) {
								value = entry.max;
								break;
							}
						value;
					})));
					final staticFields = {
						var matched:Null<RuntimeResolvedTypeSnapshot> = null;
						for (entry in resolvedTypes)
							if (entry.name == targetTypeName) {
								matched = entry;
								break;
							}
						matched == null ? [] : matched.staticFields;
					};
					parts.push(MacroProtocol.encodeLen("c", Std.string(metadata.length)));
					for (i in 0...metadata.length)
						parts.push(MacroProtocol.encodeLen("md" + i, metadata[i]));
					parts.push(MacroProtocol.encodeLen("pc", Std.string({
						var matched:Null<RuntimeResolvedTypeSnapshot> = null;
						for (entry in resolvedTypes)
							if (entry.name == targetTypeName) {
								matched = entry;
								break;
							}
						matched == null ? 0 : matched.typeParamNames.length;
					})));
					{
						var matched:Null<RuntimeResolvedTypeSnapshot> = null;
						for (entry in resolvedTypes)
							if (entry.name == targetTypeName) {
								matched = entry;
								break;
							}
						if (matched != null) {
							for (i in 0...matched.typeParamNames.length)
								parts.push(MacroProtocol.encodeLen("pn" + i, matched.typeParamNames[i]));
							if (matched.underlyingTypeText != null && matched.underlyingTypeText.length > 0)
								parts.push(MacroProtocol.encodeLen("ut", matched.underlyingTypeText));
						}
					}
					parts.push(MacroProtocol.encodeLen("sc", Std.string(staticFields.length)));
					for (i in 0...staticFields.length) {
						final entry = staticFields[i];
						parts.push(MacroProtocol.encodeLen("sn" + i, entry.name));
						parts.push(MacroProtocol.encodeLen("sk" + i, entry.kind));
						parts.push(MacroProtocol.encodeLen("sf" + i, entry.file));
						parts.push(MacroProtocol.encodeLen("smin" + i, Std.string(entry.min)));
						parts.push(MacroProtocol.encodeLen("smax" + i, Std.string(entry.max)));
						if (entry.initExpr != null && entry.initExpr.length > 0)
							parts.push(MacroProtocol.encodeLen("se" + i, entry.initExpr));
						if (entry.returnTypeText != null && entry.returnTypeText.length > 0)
							parts.push(MacroProtocol.encodeLen("sr" + i, entry.returnTypeText));
						parts.push(MacroProtocol.encodeLen("sac" + i, Std.string(entry.args.length)));
						for (j in 0...entry.args.length) {
							final arg = entry.args[j];
							parts.push(MacroProtocol.encodeLen("san" + i + "_" + j, arg.name));
							parts.push(MacroProtocol.encodeLen("sao" + i + "_" + j, arg.opt ? "1" : "0"));
							parts.push(MacroProtocol.encodeLen("sat" + i + "_" + j, arg.typeText));
						}
						parts.push(MacroProtocol.encodeLen("smc" + i, Std.string(entry.metadata.length)));
						for (j in 0...entry.metadata.length)
							parts.push(MacroProtocol.encodeLen("smd" + i + "_" + j, entry.metadata[j]));
					}
					replyOk(id, MacroProtocol.encodeLen("v", parts.join(" ")));
				case "context.getModule":
					final name = MacroProtocol.kvGet(tail, "n");
					if (name == null || name.length == 0) {
						replyErr(id, method + ": missing module name");
						return;
					}
					final classPaths = MacroState.listClassPaths();
					final cfg = MacroState.getCompilerConfigurationSnapshot();
					for (cp in cfg.stdPath)
						if (classPaths.indexOf(cp) == -1)
							classPaths.push(cp);
					final resolved = hxhx.Stage1Compiler.Stage1Resolver.resolveModule(classPaths, name, Sys.getCwd());
					if (resolved == null) {
						replyOk(id, MacroProtocol.encodeLen("v", ""));
						return;
					}
					final resolvedFields = MacroHostClient.scanResolvedModuleFields(resolved.path);
					final resolvedTypes = MacroHostClient.scanResolvedModuleTypes(name, resolved.path, resolved.className, resolvedFields.length == 0);
					final parts = new Array<String>();
					parts.push(MacroProtocol.encodeLen("ok", "1"));
					parts.push(MacroProtocol.encodeLen("m", name));
					parts.push(MacroProtocol.encodeLen("tc", Std.string(resolvedTypes.length)));
					for (i in 0...resolvedTypes.length) {
						final entry = resolvedTypes[i];
						parts.push(MacroProtocol.encodeLen("tn" + i, entry.name));
						parts.push(MacroProtocol.encodeLen("tk" + i, entry.kind));
						parts.push(MacroProtocol.encodeLen("tf" + i, entry.file));
						parts.push(MacroProtocol.encodeLen("tmin" + i, Std.string(entry.min)));
						parts.push(MacroProtocol.encodeLen("tmax" + i, Std.string(entry.max)));
						parts.push(MacroProtocol.encodeLen("tmc" + i, Std.string(entry.metadata.length)));
						parts.push(MacroProtocol.encodeLen("tpc" + i, Std.string(entry.typeParamNames.length)));
						for (j in 0...entry.metadata.length)
							parts.push(MacroProtocol.encodeLen("tmd" + i + "_" + j, entry.metadata[j]));
						for (j in 0...entry.typeParamNames.length)
							parts.push(MacroProtocol.encodeLen("tpn" + i + "_" + j, entry.typeParamNames[j]));
						if (entry.underlyingTypeText != null && entry.underlyingTypeText.length > 0)
							parts.push(MacroProtocol.encodeLen("tut" + i, entry.underlyingTypeText));
						parts.push(MacroProtocol.encodeLen("tsc" + i, Std.string(entry.staticFields.length)));
						for (j in 0...entry.staticFields.length) {
							final field = entry.staticFields[j];
							parts.push(MacroProtocol.encodeLen("tsn" + i + "_" + j, field.name));
							parts.push(MacroProtocol.encodeLen("tsk" + i + "_" + j, field.kind));
							parts.push(MacroProtocol.encodeLen("tsf" + i + "_" + j, field.file));
							parts.push(MacroProtocol.encodeLen("tsmin" + i + "_" + j, Std.string(field.min)));
							parts.push(MacroProtocol.encodeLen("tsmax" + i + "_" + j, Std.string(field.max)));
							if (field.initExpr != null && field.initExpr.length > 0)
								parts.push(MacroProtocol.encodeLen("tse" + i + "_" + j, field.initExpr));
							if (field.returnTypeText != null && field.returnTypeText.length > 0)
								parts.push(MacroProtocol.encodeLen("tsr" + i + "_" + j, field.returnTypeText));
							parts.push(MacroProtocol.encodeLen("tsac" + i + "_" + j, Std.string(field.args.length)));
							for (k in 0...field.args.length) {
								final arg = field.args[k];
								parts.push(MacroProtocol.encodeLen("tsan" + i + "_" + j + "_" + k, arg.name));
								parts.push(MacroProtocol.encodeLen("tsao" + i + "_" + j + "_" + k, arg.opt ? "1" : "0"));
								parts.push(MacroProtocol.encodeLen("tsat" + i + "_" + j + "_" + k, arg.typeText));
							}
							parts.push(MacroProtocol.encodeLen("tsmc" + i + "_" + j, Std.string(field.metadata.length)));
							for (k in 0...field.metadata.length)
								parts.push(MacroProtocol.encodeLen("tsmd" + i + "_" + j + "_" + k, field.metadata[k]));
						}
					}
					parts.push(MacroProtocol.encodeLen("fc", Std.string(resolvedFields.length)));
					for (i in 0...resolvedFields.length) {
						final entry = resolvedFields[i];
						parts.push(MacroProtocol.encodeLen("fn" + i, entry.name));
						parts.push(MacroProtocol.encodeLen("fk" + i, entry.kind));
						parts.push(MacroProtocol.encodeLen("ff" + i, entry.file));
						parts.push(MacroProtocol.encodeLen("fmin" + i, Std.string(entry.min)));
						parts.push(MacroProtocol.encodeLen("fmax" + i, Std.string(entry.max)));
						if (entry.initExpr != null && entry.initExpr.length > 0)
							parts.push(MacroProtocol.encodeLen("fe" + i, entry.initExpr));
						if (entry.returnTypeText != null && entry.returnTypeText.length > 0)
							parts.push(MacroProtocol.encodeLen("fr" + i, entry.returnTypeText));
						parts.push(MacroProtocol.encodeLen("fac" + i, Std.string(entry.args.length)));
						for (j in 0...entry.args.length) {
							final arg = entry.args[j];
							parts.push(MacroProtocol.encodeLen("fan" + i + "_" + j, arg.name));
							parts.push(MacroProtocol.encodeLen("fao" + i + "_" + j, arg.opt ? "1" : "0"));
							parts.push(MacroProtocol.encodeLen("fat" + i + "_" + j, arg.typeText));
						}
						parts.push(MacroProtocol.encodeLen("fmc" + i, Std.string(entry.metadata.length)));
						for (j in 0...entry.metadata.length)
							parts.push(MacroProtocol.encodeLen("fmd" + i + "_" + j, entry.metadata[j]));
					}
					replyOk(id, MacroProtocol.encodeLen("v", parts.join(" ")));
				case "context.getClassPath":
					final classPaths = gatherMacroContextClassPaths();
					final parts = new Array<String>();
					parts.push(MacroProtocol.encodeLen("c", Std.string(classPaths.length)));
					for (i in 0...classPaths.length)
						parts.push(MacroProtocol.encodeLen("p" + i, classPaths[i]));
					replyOk(id, MacroProtocol.encodeLen("v", parts.join(" ")));
				case "context.resolvePath":
					final file = MacroProtocol.kvGet(tail, "f");
					if (file == null || file.length == 0) {
						replyErr(id, method + ": missing file");
						return;
					}
					final resolved = resolveMacroContextPath(file);
					replyOk(id, MacroProtocol.encodeLen("v", resolved == null ? "" : resolved));
				case "context.getBuildFields":
					// Stage4 bring-up: expose the compiler-side build-field snapshot for the current
					// `@:build(...)` expansion context.
					//
					// Payload is a length-prefixed fragment list stored in `MacroState` (bring-up only).
					final payload = MacroState.getBuildFieldsPayload();
					replyOk(id, MacroProtocol.encodeLen("v", payload == null ? "" : payload));
				case "context.getDefines":
					final pairs = MacroState.listDefinesPairsSorted();
					final parts = new Array<String>();
					parts.push(MacroProtocol.encodeLen("c", Std.string(pairs.length)));
					for (i in 0...pairs.length) {
						final kv = pairs[i];
						parts.push(MacroProtocol.encodeLen("k" + i, kv[0]));
						parts.push(MacroProtocol.encodeLen("v" + i, kv[1]));
					}
					replyOk(id, MacroProtocol.encodeLen("v", parts.join(" ")));
				case "context.getResources":
					final pairs = MacroState.listResourcesPairsSorted();
					final parts = new Array<String>();
					parts.push(MacroProtocol.encodeLen("c", Std.string(pairs.length)));
					for (i in 0...pairs.length) {
						final kv = pairs[i];
						parts.push(MacroProtocol.encodeLen("k" + i, kv.name));
						parts.push(MacroProtocol.encodeLen("d" + i, kv.data.toHex()));
					}
					replyOk(id, MacroProtocol.encodeLen("v", parts.join(" ")));
				case "context.getMessages":
					final snapshots = MacroState.listMessages();
					final parts = new Array<String>();
					parts.push(MacroProtocol.encodeLen("c", Std.string(snapshots.length)));
					for (i in 0...snapshots.length) {
						final snapshot = snapshots[i];
						parts.push(MacroProtocol.encodeLen("k" + i, snapshot.kind));
						parts.push(MacroProtocol.encodeLen("m" + i, snapshot.msg));
						parts.push(MacroProtocol.encodeLen("f" + i, snapshot.pos.file));
						parts.push(MacroProtocol.encodeLen("mi" + i, Std.string(snapshot.pos.min)));
						parts.push(MacroProtocol.encodeLen("ma" + i, Std.string(snapshot.pos.max)));
					}
					replyOk(id, MacroProtocol.encodeLen("v", parts.join(" ")));
				case "context.replaceMessages":
					final payload = MacroProtocol.kvGet(tail, "p");
					final parts = MacroProtocol.kvParse(payload == null ? "" : payload);
					final count = Std.parseInt(parts.exists("c") ? parts.get("c") : "0");
					final next = new Array<{
						kind:String,
						msg:String,
						pos:{
							file:String,
							min:Int,
							max:Int
						}
					}>();
					if (count != null && count > 0) {
						for (i in 0...count) {
							if (!parts.exists("k" + i) || !parts.exists("m" + i))
								continue;
							final min = Std.parseInt(parts.exists("mi" + i) ? parts.get("mi" + i) : "0");
							final max = Std.parseInt(parts.exists("ma" + i) ? parts.get("ma" + i) : "0");
							next.push({
								kind: parts.get("k" + i),
								msg: parts.get("m" + i),
								pos: {
									file: parts.exists("f" + i) && parts.get("f" + i).length > 0 ? parts.get("f" + i) : "<macro>",
									min: min == null || min < 0 ? 0 : min,
									max: max == null || max < 0 ? 0 : max}
							});
						}
					}
					MacroState.replaceMessages(next);
					replyOk(id, MacroProtocol.encodeLen("v", "ok"));
				case _:
					replyErr(id, "unknown method: " + method);
			}
		} catch (e:haxe.io.Error) {
			replyErr(id, method + ": exception: " + Std.string(e));
		} catch (e:String) {
			replyErr(id, method + ": exception: " + e);
		}
	}

	inline function replyOk(id:Int, tail:String):Void {
		proc.stdin.writeString("res " + id + " ok " + tail + "\n", null);
		proc.stdin.flush();
	}

	static inline function optionalText(value:Null<String>):String {
		return value == null ? "" : value;
	}

	static function gatherMacroContextClassPaths():Array<String> {
		final out = MacroState.listClassPaths();
		final cfg = MacroState.getCompilerConfigurationSnapshot();
		for (cp in cfg.stdPath)
			if (out.indexOf(cp) == -1)
				out.push(cp);
		return out;
	}

	static function encodeLocalImportsPayload():String {
		final buildFile = resolveMacroContextBuildFile();
		if (buildFile == null || buildFile.length == 0)
			return MacroProtocol.encodeLen("c", "0");
		return MacroLocalImports.encodePayloadFromSourceFile(buildFile);
	}

	static function encodeLocalUsingsPayload():String {
		final buildFile = resolveMacroContextBuildFile();
		if (buildFile == null || buildFile.length == 0)
			return MacroProtocol.encodeLen("c", "0");
		return MacroLocalImports.encodeUsingsPayloadFromSourceFile(buildFile);
	}

	static function encodeLocalTVarsPayload():String {
		final entries = MacroState.listLocalTVars();
		if (entries.length == 0)
			return MacroProtocol.encodeLen("c", "0");
		final parts = new Array<String>();
		parts.push(MacroProtocol.encodeLen("c", Std.string(entries.length)));
		for (i in 0...entries.length) {
			final entry = entries[i];
			parts.push(MacroProtocol.encodeLen("n" + i, entry.name));
			parts.push(MacroProtocol.encodeLen("t" + i, entry.typeText));
			parts.push(MacroProtocol.encodeLen("id" + i, Std.string(entry.id == null ? 0 : entry.id)));
			parts.push(MacroProtocol.encodeLen("cap" + i, entry.capture == true ? "1" : "0"));
			parts.push(MacroProtocol.encodeLen("st" + i, entry.isStatic == true ? "1" : "0"));
		}
		return parts.join(" ");
	}

	static function encodeCallArgumentsPayload():String {
		final exprs = MacroState.listCallArgumentExprTexts();
		if (exprs.length == 0)
			return MacroProtocol.encodeLen("c", "0");
		final parts = new Array<String>();
		parts.push(MacroProtocol.encodeLen("c", Std.string(exprs.length)));
		for (i in 0...exprs.length)
			parts.push(MacroProtocol.encodeLen("e" + i, exprs[i]));
		return parts.join(" ");
	}

	static function resolveMacroContextBuildFile():Null<String> {
		final explicitBuildFile = MacroState.definedValue("HXHX_BUILD_FILE");
		if (explicitBuildFile != null && explicitBuildFile.length > 0) {
			final resolved = resolveMacroContextPath(explicitBuildFile);
			if (resolved != null && resolved.length > 0)
				return resolved;
		}

		final pos = MacroState.getCurrentPos();
		final posFile = pos == null ? "" : pos.file;
		if (posFile == null || posFile.length == 0 || posFile == "<macro>")
			return null;
		return resolveMacroContextPath(posFile);
	}

	static function resolveMacroContextPath(file:String):Null<String> {
		final trimmed = StringTools.trim(file == null ? "" : file);
		if (trimmed.length == 0)
			return null;

		final normalized = StringTools.replace(trimmed, "\\", "/");
		try {
			if (haxe.io.Path.isAbsolute(normalized) && sys.FileSystem.exists(normalized) && !sys.FileSystem.isDirectory(normalized))
				return sys.FileSystem.fullPath(normalized);
		} catch (_:String) {}

		final cwd = Sys.getCwd();
		final repoRelative = haxe.io.Path.normalize(haxe.io.Path.join([cwd, normalized]));
		try {
			if (sys.FileSystem.exists(repoRelative) && !sys.FileSystem.isDirectory(repoRelative))
				return sys.FileSystem.fullPath(repoRelative);
		} catch (_:String) {}

		for (cp in gatherMacroContextClassPaths()) {
			final cp0 = StringTools.replace(cp == null ? "" : cp, "\\", "/");
			final base = haxe.io.Path.isAbsolute(cp0) ? cp0 : haxe.io.Path.normalize(haxe.io.Path.join([cwd, cp0]));
			final candidate = haxe.io.Path.normalize(haxe.io.Path.join([base, normalized]));
			try {
				if (sys.FileSystem.exists(candidate) && !sys.FileSystem.isDirectory(candidate))
					return sys.FileSystem.fullPath(candidate);
			} catch (_:String) {}
		}

		return null;
	}

	inline function replyErr(id:Int, msg:String):Void {
		proc.stdin.writeString("res " + id + " err " + MacroProtocol.encodeLen("m", msg) + " " + MacroProtocol.encodeLen("p", "") + "\n", null);
		proc.stdin.flush();
	}

	public function close():Void {
		if (timeoutTriggered)
			return;

		try {
			proc.stdin.writeString("quit\n", null);
			proc.stdin.flush();
		} catch (_:haxe.io.Error) {} catch (_:String) {}

		// Optional bring-up diagnostics: if the macro host logs to stderr (e.g. reverse-RPC tracing),
		// drain it after requesting shutdown so the output is visible in CI logs.
		if (TRACE_HOST) {
			try {
				while (true) {
					final line = proc.stderr.readLine();
					Sys.stderr().writeString(line + "\n");
				}
			} catch (_:haxe.io.Eof) {
				// expected
			} catch (_:haxe.io.Error) {} catch (_:String) {}
		}

		proc.close();
	}
}

/**
	Public wrapper around a single macro host process.

	Why
	- Stage3 needs to keep the macro host alive across phases so registered hook closures can run.

	What
	- `run(expr)`: calls `macro.run` and returns the `v=` payload.
	- `runHook(kind,id)`: calls `macro.runHook` to execute a previously-registered hook closure.
**/
class MacroHostSession implements MacroRuntimeSession {
	final client:MacroClient;

	public function new(client:MacroClient) {
		this.client = client;
	}

	public function run(expr:String):String {
		return client.call("macro.run", MacroProtocol.encodeLen("e", expr));
	}

	public function loadNativeModule(modulePath:String, pluginId:String):Array<String> {
		final payload = client.call("macro.loadNativeModule", MacroProtocol.encodeLen("p", modulePath) + " " + MacroProtocol.encodeLen("i", pluginId));
		final parts = MacroProtocol.kvParse(payload == null ? "" : payload);
		final countStr = parts.exists("c") ? parts.get("c") : "0";
		final count = Std.parseInt(countStr);
		if (count == null || count < 0)
			throw "macro host: invalid native module expr count payload: " + countStr;
		final out = new Array<String>();
		for (i in 0...count) {
			final key = "e" + i;
			if (!parts.exists(key))
				throw "macro host: missing native module expr payload key: " + key;
			out.push(parts.get(key));
		}
		return out;
	}

	public function runNativeExpr(expr:String):String {
		return client.call("macro.runNativeExpr", MacroProtocol.encodeLen("e", expr));
	}

	/**
		Expand an allowlisted “expression macro” call.

		Why
		- Expression macros are a core upstream feature: a call in normal code is executed at compile time
		  and replaced with the returned expression.
		- Stage4 bring-up models this by executing the call out-of-process (macro host) and returning
		  a Haxe expression text snippet for the compiler to parse into the bootstrap AST.

		What
		- Calls RPC `macro.expandExpr` with:
		  - `e`: the *exact* call text (e.g. `pack.Mod.meth()`).
		- Returns a Haxe expression text snippet (e.g. `"hello"` or `0`).

		Gotchas
		- This is a bring-up ABI. Today it is:
		  - allowlist-only (exact expression match),
		  - limited to a small expression grammar on the compiler side.
	**/
	public function expandExpr(expr:String):String {
		return client.call("macro.expandExpr", MacroProtocol.encodeLen("e", expr));
	}

	public function runHook(kind:String, id:Int):Void {
		final tail = MacroProtocol.encodeLen("k", kind == null ? "" : kind) + " " + MacroProtocol.encodeLen("i", Std.string(id));
		client.call("macro.runHook", tail);
	}

	public function runTypeNotFoundHook(id:Int, typePath:String):Bool {
		final tail = MacroProtocol.encodeLen("i", Std.string(id)) + " " + MacroProtocol.encodeLen("n", typePath == null ? "" : typePath);
		return client.call("macro.runTypeNotFoundHook", tail) == "1";
	}

	public function close():Void {
		client.close();
	}
}
