package hxhx.macro;

typedef RuntimeResolvedTypeSnapshot = {
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

typedef RuntimeResolvedTypeSemantics = {
	final typeParamNames:Array<String>;
	final underlyingTypeText:Null<String>;
}

typedef RuntimeResolvedModuleFieldSnapshot = {
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

typedef RuntimeResolvedModuleImportSnapshot = {
	final path:String;
	final localName:String;
}

/**
	Compiler-side scanners used by external-host macro runtime payloads.

	Why
	- Current-source native macro-host builds exposed an OCaml lowering seam where some
	  same-class static helper calls inside `MacroHostClient` were emitted as bare local
	  function references and then reordered into unbound uses.
	- These scanners are pure compiler-side source/classpath helpers. Keeping them in a
	  dedicated module avoids that fragile same-class codegen path without changing behavior.

	What
	- Owns filtered-source scans for resolved modules:
	  - top-level type declarations
	  - module fields
	  - imports/usings
	  - typedef/abstract payload semantics
	  - static-field scans for synthetic runtime refs

	How
	- Reuses the existing parser/conditional-compilation helpers and compiler-owned define
	  snapshots from `MacroState`.
	- Returns narrow deterministic payload records consumed by `MacroHostClient` and the
	  external-host runtime bridge.
 */
class MacroResolvedModuleScanner {
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
		var bodyEnd = scanTopLevelTypeTerminator(source, bodyStart, ";".code);
		if (bodyEnd < 0 && bodyStart < source.length && source.charCodeAt(bodyStart) == "{".code)
			bodyEnd = scanBalancedText(source, bodyStart, "{".code, "}".code);
		if (bodyEnd < 0)
			return null;
		return {
			name: name,
			typeParamNames: typeParamNames,
			underlyingTypeText: StringTools.trim(source.substr(bodyStart, bodyEnd - bodyStart)),
			nextIndex: bodyEnd < source.length && source.charCodeAt(bodyEnd) == ";".code ? bodyEnd + 1 : bodyEnd};
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

	/**
		Scan narrow top-level imports/usings from filtered source.

		Why
		- Runtime `Context.getModule(...)` field-signature reconstruction needs the module's local
		  import scope so bare names like `Assigns<CardAssigns>` can resolve semantically instead of
		  degrading to fake bare paths.

		What
		- Captures top-level `import` / `using` statements before/alongside type declarations.
		- Preserves `as Alias` local names when present.

		Gotchas
		- Wildcards are ignored.
		- This is still a narrow scanner, not full import semantics.
	**/
	public static function scanResolvedModuleImports(path:String):Array<RuntimeResolvedModuleImportSnapshot> {
		final out = new Array<RuntimeResolvedModuleImportSnapshot>();
		final filtered = readFilteredResolvedModuleSource(path);
		if (filtered.length == 0)
			return out;

		final seen = new Map<String, Bool>();
		var braceDepth = 0;
		var blockCommentDepth = 0;
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

		function push(pathText:String, ?alias:Null<String>):Void {
			final trimmedPath = StringTools.trim(pathText == null ? "" : pathText);
			if (trimmedPath.length == 0 || StringTools.endsWith(trimmedPath, ".*"))
				return;
			final parts = trimmedPath.split(".");
			final localName = {
				final trimmedAlias = StringTools.trim(alias == null ? "" : alias);
				trimmedAlias.length > 0 ? trimmedAlias : (parts.length == 0 ? trimmedPath : parts[parts.length - 1]);
			}
			final key = trimmedPath + "=>" + localName;
			if (seen.exists(key))
				return;
			seen.set(key, true);
			out.push({
				path: trimmedPath,
				localName: localName
			});
		}

		for (rawLine in lines) {
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
				continue;
			}

			if (braceDepth == 0) {
				if (StringTools.startsWith(trimmed, "import ")) {
					var body = StringTools.trim(trimmed.substr("import ".length));
					if (StringTools.endsWith(body, ";"))
						body = StringTools.trim(body.substr(0, body.length - 1));
					final asIndex = body.indexOf(" as ");
					if (asIndex >= 0)
						push(body.substr(0, asIndex), body.substr(asIndex + 4));
					else
						push(body);
				} else if (StringTools.startsWith(trimmed, "using ")) {
					var body = StringTools.trim(trimmed.substr("using ".length));
					if (StringTools.endsWith(body, ";"))
						body = StringTools.trim(body.substr(0, body.length - 1));
					push(body);
				}
			}

			braceDepth += countChar(line, "{");
			braceDepth -= countChar(line, "}");
			if (braceDepth < 0)
				braceDepth = 0;
		}

		return out;
	}

	/**
		Encode the compiler-side `context.getType` payload for a runtime macro lookup.

		Why
		- The external-host runtime reconstructs synthetic `Type` values from this payload, so focused
		  direct integration tests should be able to reuse the exact same encoder instead of drifting
		  into a fake path-only fallback.
		- Keeping the encoder in one place avoids semantic skew between the live RPC handler and
		  test-local reverse-RPC shims.
	**/
	public static function encodeContextGetTypePayload(name:String):String {
		if (name == null || name.length == 0)
			return "";
		final classPaths = MacroState.listClassPaths();
		final cfg = MacroState.getCompilerConfigurationSnapshot();
		for (cp in cfg.stdPath)
			if (classPaths.indexOf(cp) == -1)
				classPaths.push(cp);
		final resolved = hxhx.Stage1Compiler.Stage1Resolver.resolveModule(classPaths, name, Sys.getCwd());
		if (resolved == null)
			return "";
		final resolvedTypes = scanResolvedModuleTypes(name, resolved.path, resolved.className);
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
		var matchedTypeParamCount = 0;
		{
			var matched:Null<RuntimeResolvedTypeSnapshot> = null;
			for (entry in resolvedTypes)
				if (entry.name == targetTypeName) {
					matched = entry;
					break;
				}
			if (matched != null)
				matchedTypeParamCount = matched.typeParamNames.length;
		}
		parts.push(MacroProtocol.encodeLen("pc", Std.string(matchedTypeParamCount)));
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
		return parts.join(" ");
	}
}
