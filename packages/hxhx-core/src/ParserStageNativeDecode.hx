/**
	Native protocol decoder extracted from `ParserStage`.

	Why
	- `ParserStage` is a large hotspot compile unit in stage0 memory probes.
	- Keeping protocol decode logic in a separate module lets us A/B parser compile-graph size
	  (`hxhx_stage0_no_native_decode_extract`) without changing runtime behavior.

	How
	- Default path: `ParserStage` delegates protocol decoding to this module.
	- Profiling baseline path: `-D hxhx_stage0_no_native_decode_extract` uses inline decode
	  methods in `ParserStage` for parity-aware A/B comparison.
**/
class ParserStageNativeDecode {
	/**
		Decode the native frontend protocol emitted by the OCaml lexer/parser stubs.

		Why:
		- This is our “bootstrap seam” for Haxe-in-Haxe: we want to keep the
		  frontend native initially, but keep the rest of the compiler in Haxe.

		What:
		- Produces a `HxModuleDecl` for Stage 2 from the protocol output.

		How:
		- The protocol is intentionally simple and line-based so it can be produced
		  from OCaml without dependencies and decoded from Haxe without a JSON
		  runtime.
		- See `docs/02-user-guide/HXHX_NATIVE_FRONTEND_PROTOCOL.md:1` for the exact
		  wire format and versioning rules.
	**/
	public static function decodeNativeProtocol(encoded:String, ?source:String):HxModuleDecl {
		final lines = encoded.split("\n").filter(l -> l.length > 0);
		if (lines.length == 0) {
			throw "Native frontend: missing/invalid protocol header";
		}
		final header = lines[0];
		if (header != "hxhx_frontend_v=1" && header != "hxhx_frontend_v=2") {
			throw "Native frontend: missing/invalid protocol header";
		}

		var packagePath = "";
		final imports = new Array<String>();
		var className = "Unknown";
		var headerOnly = false;
		var hasToplevelMain = false;
		var hasStaticMain = false;
		final methodPayloads = new Array<String>();
		final fieldPayloads = new Array<String>();
		final staticFinalPayloads = new Array<String>();
		final methodBodies:Map<String, Array<String>> = [];
		final methodBodyStarts:Map<String, Array<Int>> = [];
		final functions = new Array<HxFunctionDecl>();
		final fields = new Array<HxFieldDecl>();
		var sawOk = false;

		for (i in 1...lines.length) {
			final line = lines[i];
			if (line == "ok") {
				sawOk = true;
				continue;
			}

			if (StringTools.startsWith(line, "err ")) {
				throwFromErrLine(line);
				return null;
			}

			if (StringTools.startsWith(line, "ast ")) {
				if (StringTools.startsWith(line, "ast static_main ")) {
					hasStaticMain = line.substr("ast static_main ".length) == "1";
					continue;
				}

				final rest = line.substr("ast ".length);
				final firstSpace = rest.indexOf(" ");
				if (firstSpace <= 0)
					continue;
				final key = rest.substr(0, firstSpace);
				final payload = decodeLenPayload(rest.substr(firstSpace + 1));
				switch (key) {
					case "package":
						packagePath = payload;
					case "imports":
						if (payload.length > 0) {
							for (p in payload.split("|"))
								if (p.length > 0)
									imports.push(p);
						}
					case "class":
						className = payload;
					case "header_only":
						headerOnly = payload == "1";
					case "toplevel_main":
						hasToplevelMain = payload == "1";
					case "method":
						methodPayloads.push(payload);
					case "field":
						fieldPayloads.push(payload);
					case "static_final":
						staticFinalPayloads.push(payload);
					case "method_body":
						// Payload format: "<methodName>\n<bodySource>"
						final nl = payload.indexOf("\n");
						if (nl > 0) {
							final name = payload.substr(0, nl);
							final bodySource = payload.substr(nl + 1);
							var bodies = methodBodies.get(name);
							if (bodies == null) {
								bodies = [];
								methodBodies.set(name, bodies);
							}
							bodies.push(bodySource);
							var starts = methodBodyStarts.get(name);
							if (starts == null) {
								starts = [];
								methodBodyStarts.set(name, starts);
							}
							var start = -1;
							if (source != null && source.length > 0 && bodySource.length > 0) {
								final bodyStart = source.indexOf(bodySource);
								final fallbackStart = findFunctionBodyStart(source, name);
								start = bodyStart >= 0 ? bodyStart : fallbackStart;
							}
							starts.push(start);
						}
					case _:
				}
				continue;
			}
		}

		if (!sawOk) {
			throw "Native frontend: missing terminal 'ok'";
		}

		final sourceFieldHints = sourceFieldTypeHints(source, className);

		final methodBodyUseCounts:Map<String, Int> = [];
		for (mp in methodPayloads) {
			final name = {
				final parts = mp.split("|");
				parts.length == 0 ? "" : parts[0];
			};
			final bodyIndex = methodBodyUseCounts.exists(name) ? methodBodyUseCounts.get(name) : 0;
			methodBodyUseCounts.set(name, bodyIndex + 1);
			final bodies = methodBodies.get(name);
			final starts = methodBodyStarts.get(name);
			functions.push(decodeMethodPayload(mp, bodies != null && bodyIndex < bodies.length ? bodies[bodyIndex] : null, starts != null && bodyIndex < starts.length ? starts[bodyIndex] : -1,
				source));
		}

		final seenFields:Map<String, Bool> = [];
		inline function pushFieldMaybe(f:Null<HxFieldDecl>) {
			if (f == null)
				return;
			final key = HxFieldDecl.getName(f) + "|" + (HxFieldDecl.getIsStatic(f) ? "1" : "0");
			if (seenFields.exists(key))
				return;
			seenFields.set(key, true);
			fields.push(f);
		}

		for (fp in staticFinalPayloads) {
			pushFieldMaybe(decodeStaticFinalPayload(fp, sourceFieldHints));
		}

		for (fp in fieldPayloads) {
			pushFieldMaybe(decodeFieldPayload(fp, false, sourceFieldHints));
		}

		final cls = new HxClassDecl(className, hasStaticMain, functions, fields);
		return new HxModuleDecl(packagePath, imports, cls, [cls], headerOnly, hasToplevelMain);
	}

	static function fieldHintKey(name:String, isStatic:Bool):String {
		return name + "|" + (isStatic ? "1" : "0");
	}

	static function expectedTypeName(expectedClass:String):String {
		final raw = StringTools.trim(expectedClass == null ? "" : expectedClass);
		final dot = raw.lastIndexOf(".");
		return dot >= 0 ? raw.substr(dot + 1) : raw;
	}

	static function sourceFieldTypeHints(?source:String, ?expectedClass:String):Map<String, String> {
		final out:Map<String, String> = [];
		if (source == null || source.length == 0)
			return out;
		scanSourceFieldTypeHints(source, expectedTypeName(expectedClass), out);
		return out;
	}

	static function scanSourceFieldTypeHints(source:String, expectedClass:String, out:Map<String, String>):Void {
		final wanted = StringTools.trim(expectedClass == null ? "" : expectedClass);
		var depth = 0;
		var pos = 0;
		while (pos < source.length) {
			final tok = ParserStageScanHelpers.scanNextToken(source, pos);
			if (tok.text.length == 0)
				break;
			pos = tok.nextPos;
			if (tok.text == "{") {
				depth += 1;
				continue;
			}
			if (tok.text == "}") {
				if (depth > 0)
					depth -= 1;
				continue;
			}
			if (depth != 0 || tok.text != "class")
				continue;
			final nameTok = ParserStageScanHelpers.scanNextToken(source, pos);
			if (!nameTok.isIdent)
				continue;
			final className = nameTok.text;
			pos = nameTok.nextPos;
			if (wanted.length > 0 && className != wanted)
				continue;
			final open = scanUntilToken(source, pos, "{");
			if (open < 0)
				return;
			scanClassFieldTypeHints(source, open, out);
			return;
		}
	}

	static function scanClassFieldTypeHints(source:String, classOpen:Int, out:Map<String, String>):Void {
		var depth = 1;
		var pos = classOpen + 1;
		var pendingStatic = false;
		while (pos < source.length && depth > 0) {
			final tok = ParserStageScanHelpers.scanNextToken(source, pos);
			if (tok.text.length == 0)
				break;
			pos = tok.nextPos;
			if (tok.text == "{") {
				depth += 1;
				pendingStatic = false;
				continue;
			}
			if (tok.text == "}") {
				depth -= 1;
				pendingStatic = false;
				continue;
			}
			if (depth != 1)
				continue;
			switch (tok.text) {
				case "public" | "private" | "inline" | "override" | "dynamic":
				case "static":
					pendingStatic = true;
				case "function":
					pendingStatic = false;
				case "var" | "final":
					final scanned = scanFieldTypeHintAfterVar(source, pos);
					if (scanned.nextPos > pos)
						pos = scanned.nextPos;
					if (scanned.name.length > 0 && scanned.typeHint.length > 0)
						out.set(fieldHintKey(scanned.name, pendingStatic), scanned.typeHint);
					pendingStatic = false;
				case _:
					pendingStatic = false;
			}
		}
	}

	static function scanFieldTypeHintAfterVar(source:String, start:Int):{name:String, typeHint:String, nextPos:Int} {
		var pos = start;
		final nameTok = ParserStageScanHelpers.scanNextToken(source, pos);
		if (!nameTok.isIdent)
			return {name: "", typeHint: "", nextPos: pos};
		final name = nameTok.text;
		pos = nameTok.nextPos;
		var typeHint = "";
		while (pos < source.length) {
			final tok = ParserStageScanHelpers.scanNextToken(source, pos);
			if (tok.text.length == 0)
				break;
			pos = tok.nextPos;
			switch (tok.text) {
				case ":":
					final end = findFieldTypeHintEnd(source, pos);
					typeHint = StringTools.trim(source.substring(pos, end));
					pos = end;
					break;
				case ";" | "=":
					break;
				case "{":
					break;
				case _:
			}
		}
		return {name: name, typeHint: typeHint, nextPos: skipToFieldBoundary(source, pos)};
	}

	static function scanUntilToken(source:String, start:Int, token:String):Int {
		var pos = start;
		while (pos < source.length) {
			final tok = ParserStageScanHelpers.scanNextToken(source, pos);
			if (tok.text.length == 0)
				return -1;
			if (tok.text == token)
				return tok.startPos;
			pos = tok.nextPos;
		}
		return -1;
	}

	static function findFieldTypeHintEnd(source:String, start:Int):Int {
		var pos = start;
		var parenDepth = 0;
		var bracketDepth = 0;
		var angleDepth = 0;
		while (pos < source.length) {
			final c = source.charCodeAt(pos);
			if (c == "\"".code || c == "'".code) {
				pos = skipQuotedSource(source, pos);
				continue;
			}
			switch (c) {
				case "(".code:
					parenDepth += 1;
				case ")".code:
					if (parenDepth > 0)
						parenDepth -= 1;
				case "[".code:
					bracketDepth += 1;
				case "]".code:
					if (bracketDepth > 0)
						bracketDepth -= 1;
				case "<".code:
					angleDepth += 1;
				case ">".code:
					if (angleDepth > 0)
						angleDepth -= 1;
				case "=".code | ";".code:
					if (parenDepth == 0 && bracketDepth == 0 && angleDepth == 0)
						return pos;
				case _:
			}
			pos += 1;
		}
		return pos;
	}

	static function skipToFieldBoundary(source:String, start:Int):Int {
		var pos = start;
		while (pos < source.length) {
			final c = source.charCodeAt(pos);
			if (c == "\"".code || c == "'".code) {
				pos = skipQuotedSource(source, pos);
				continue;
			}
			if (c == ";".code)
				return pos + 1;
			if (c == "\n".code)
				return pos + 1;
			pos += 1;
		}
		return pos;
	}

	static function skipQuotedSource(source:String, start:Int):Int {
		final quote = source.charCodeAt(start);
		var pos = start + 1;
		while (pos < source.length) {
			final c = source.charCodeAt(pos);
			if (c == "\\".code) {
				pos += 2;
				continue;
			}
			pos += 1;
			if (c == quote)
				break;
		}
		return pos;
	}

	static function sourceFieldTypeHintByName(hints:Map<String, String>, name:String, isStatic:Bool):String {
		if (hints == null || name == null || name.length == 0)
			return "";
		final key = fieldHintKey(name, isStatic);
		return hints.exists(key) ? hints.get(key) : "";
	}

	static function sourceSignatureArgHints(name:String, ?source:String, methodBodyStart:Int = -1, ?argNames:Array<String>):Array<{
		name:String,
		isOptional:Bool,
		typeHint:String,
		defaultText:String
	}> {
		if (source == null || source.length == 0 || name == null || name.length == 0)
			return [];
		final needle = "function " + name;
		function hintsAt(fnIndex:Int):Array<{
			name:String,
			isOptional:Bool,
			typeHint:String,
			defaultText:String
		}> {
			if (fnIndex < 0)
				return [];
			final open = source.indexOf("(", fnIndex);
			if (open < 0)
				return [];
			final close = findMatchingParen(source, open);
			if (close < 0)
				return [];
			return parseSourceSignatureArgs(source.substr(open + 1, close - open - 1));
		}
		final anchoredIndex = methodBodyStart > 0 ? source.lastIndexOf(needle, methodBodyStart) : -1;
		final anchoredHints = hintsAt(anchoredIndex);
		if (anchoredHints.length > 0 && sourceArgHintsMatchNames(anchoredHints, argNames))
			return anchoredHints;
		var first = new Array<{
			name:String,
			isOptional:Bool,
			typeHint:String,
			defaultText:String
		}>();
		var searchFrom = 0;
		while (searchFrom < source.length) {
			final fnIndex = source.indexOf(needle, searchFrom);
			if (fnIndex < 0)
				break;
			final hints = hintsAt(fnIndex);
			if (first.length == 0)
				first = hints;
			if (hints.length > 0 && sourceArgHintsMatchNames(hints, argNames))
				return hints;
			searchFrom = fnIndex + needle.length;
		}
		return first;
	}

	static function sourceArgHintsMatchNames(hints:Array<{
		name:String,
		isOptional:Bool,
		typeHint:String,
		defaultText:String
	}>, ?argNames:Array<String>):Bool {
		if (argNames == null || argNames.length == 0)
			return true;
		if (hints.length != argNames.length)
			return false;
		for (i in 0...argNames.length)
			if (hints[i].name != argNames[i])
				return false;
		return true;
	}

	static function protocolArgNames(argsPayload:String):Array<String> {
		final out = new Array<String>();
		if (argsPayload == null || argsPayload.length == 0)
			return out;
		for (arg in argsPayload.split(",")) {
			var name = StringTools.trim(arg);
			if (name.length == 0)
				continue;
			if (StringTools.startsWith(name, "..."))
				name = name.substr(3);
			if (StringTools.startsWith(name, "?"))
				name = name.substr(1);
			out.push(name);
		}
		return out;
	}

	static function findMatchingParen(source:String, open:Int):Int {
		var depth = 0;
		var inString = false;
		var quote = "";
		var i = open;
		while (i < source.length) {
			final ch = source.charAt(i);
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
			if (ch == "(")
				depth += 1;
			else if (ch == ")") {
				depth -= 1;
				if (depth == 0)
					return i;
			}
			i += 1;
		}
		return -1;
	}

	static function splitTopLevelComma(text:String):Array<String> {
		final out = new Array<String>();
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
			if (ch == "\"" || ch == "'") {
				inString = true;
				quote = ch;
			} else {
				switch (ch) {
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
			}
			i += 1;
		}
		out.push(text.substr(start));
		return out;
	}

	static function findTopLevelEquals(text:String):Int {
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
			if (ch == "\"" || ch == "'") {
				inString = true;
				quote = ch;
			} else {
				switch (ch) {
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
					case "=":
						if (parenDepth == 0 && bracketDepth == 0 && braceDepth == 0 && angleDepth == 0)
							return i;
					case _:
				}
			}
			i += 1;
		}
		return -1;
	}

	static function parseSourceSignatureArgs(text:String):Array<{
		name:String,
		isOptional:Bool,
		typeHint:String,
		defaultText:String
	}> {
		final out = new Array<{
			name:String,
			isOptional:Bool,
			typeHint:String,
			defaultText:String
		}>();
		for (segment in splitTopLevelComma(text)) {
			var working = StringTools.trim(segment);
			if (working.length == 0)
				continue;
			if (StringTools.startsWith(working, "..."))
				working = StringTools.trim(working.substr(3));
			var isOptional = false;
			if (StringTools.startsWith(working, "?")) {
				isOptional = true;
				working = StringTools.trim(working.substr(1));
			}
			final nameMatch = ~/^([A-Za-z_][A-Za-z0-9_]*)/;
			if (!nameMatch.match(working))
				continue;
			final argName = nameMatch.matched(1);
			final afterName = StringTools.trim(working.substr(nameMatch.matchedPos().pos + nameMatch.matchedPos().len));
			final eqIndex = findTopLevelEquals(afterName);
			final typeSource = eqIndex >= 0 ? StringTools.trim(afterName.substr(0, eqIndex)) : afterName;
			final typeHint = StringTools.startsWith(typeSource, ":") ? StringTools.trim(typeSource.substr(1)) : "";
			final defaultText = eqIndex >= 0 ? StringTools.trim(afterName.substr(eqIndex + 1)) : "";
			out.push({
				name: argName,
				isOptional: isOptional || defaultText.length > 0,
				typeHint: typeHint,
				defaultText: defaultText
			});
		}
		return out;
	}

	static function sourceArgHintByName(hints:Array<{
		name:String,
		isOptional:Bool,
		typeHint:String,
		defaultText:String
	}>, name:String):Null<{
		name:String,
		isOptional:Bool,
		typeHint:String,
		defaultText:String
	}> {
		for (hint in hints)
			if (hint.name == name)
				return hint;
		return null;
	}

	static function compactTypeHint(typeHint:String):String {
		var compact = StringTools.trim(typeHint == null ? "" : typeHint);
		compact = StringTools.replace(compact, " ", "");
		compact = StringTools.replace(compact, "\t", "");
		compact = StringTools.replace(compact, "\r", "");
		compact = StringTools.replace(compact, "\n", "");
		return compact;
	}

	static function sourceTypeHintIsMoreSpecific(nativeTypeHint:String, sourceTypeHint:String):Bool {
		final source = compactTypeHint(sourceTypeHint);
		if (source.length == 0)
			return false;
		final native = compactTypeHint(nativeTypeHint);
		if (native.length == 0)
			return true;
		if (isFunctionTypeHintText(source) && isErasedFunctionTypeHintText(native))
			return true;
		if (isStructuralTypeHintText(source) && isErasedStructuralFallbackTypeHint(native))
			return true;
		final sourceIsNull = StringTools.startsWith(source, "Null<") || StringTools.startsWith(source, "StdTypes.Null<");
		if ((native == "Null" || native == "StdTypes.Null") && sourceIsNull)
			return true;
		if (!sourceIsNull)
			return false;
		final inner = StringTools.startsWith(source,
			"Null<") ? source.substr("Null<".length,
				source.length - "Null<".length - 1) : source.substr("StdTypes.Null<".length, source.length - "StdTypes.Null<".length - 1);
		return native == inner || StringTools.endsWith(native, "." + inner);
	}

	static function sourceArgTypeHintIsMoreSpecific(nativeTypeHint:String, sourceTypeHint:String):Bool {
		if (sourceTypeHintIsMoreSpecific(nativeTypeHint, sourceTypeHint))
			return true;
		final native = compactTypeHint(nativeTypeHint);
		final source = compactTypeHint(sourceTypeHint);
		return (native == "String" || native == "StdTypes.String") && isFunctionTypeHintText(source);
	}

	static function isStructuralTypeHintText(typeHint:String):Bool {
		return StringTools.startsWith(typeHint, "{") && StringTools.endsWith(typeHint, "}");
	}

	static function isErasedStructuralFallbackTypeHint(typeHint:String):Bool {
		return typeHint == "String" || typeHint == "StdTypes.String" || typeHint == "Dynamic" || typeHint == "Any";
	}

	static function isFunctionTypeHintText(typeHint:String):Bool {
		return typeHint.indexOf("->") >= 0;
	}

	static function isErasedFunctionTypeHintText(typeHint:String):Bool {
		return typeHint == "Dynamic"
			|| typeHint == "Any"
			|| typeHint == "Function"
			|| typeHint == "StdTypes.Function"
			|| typeHint == "haxe.Constraints.Function"
			|| StringTools.endsWith(typeHint, ".Function")
			|| (!isKnownConcreteTypeHintText(typeHint) && isGenericTypeVariableHintText(typeHint));
	}

	static function isKnownConcreteTypeHintText(typeHint:String):Bool {
		return typeHint == "String" || typeHint == "Bool" || typeHint == "Int" || typeHint == "Float" || typeHint == "Array"
			|| typeHint == "StdTypes.String" || typeHint == "StdTypes.Bool" || typeHint == "StdTypes.Int" || typeHint == "StdTypes.Float";
	}

	static function isGenericTypeVariableHintText(typeHint:String):Bool {
		if (typeHint == null || typeHint.length == 0 || typeHint.indexOf(".") >= 0)
			return false;
		final first = typeHint.charCodeAt(0);
		if (first < "A".code || first > "Z".code)
			return false;
		for (i in 1...typeHint.length) {
			final code = typeHint.charCodeAt(i);
			final isLetter = (code >= "A".code && code <= "Z".code) || (code >= "a".code && code <= "z".code);
			final isDigit = code >= "0".code && code <= "9".code;
			if (!isLetter && !isDigit && code != "_".code)
				return false;
		}
		return true;
	}

	static function defaultValueFromText(text:String):HxDefaultValue {
		final trimmed = StringTools.trim(text == null ? "" : text);
		if (trimmed.length == 0)
			return HxDefaultValue.NoDefault;
		if (trimmed == "null")
			return HxDefaultValue.Default(HxExpr.ENull);
		if (trimmed == "true")
			return HxDefaultValue.Default(HxExpr.EBool(true));
		if (trimmed == "false")
			return HxDefaultValue.Default(HxExpr.EBool(false));
		final first = trimmed.charAt(0);
		final last = trimmed.charAt(trimmed.length - 1);
		if ((first == "\"" && last == "\"") || (first == "'" && last == "'"))
			return HxDefaultValue.Default(HxExpr.EString(trimmed.substr(1, trimmed.length - 2)));
		final intValue = Std.parseInt(trimmed);
		if (intValue != null && Std.string(intValue) == trimmed)
			return HxDefaultValue.Default(HxExpr.EInt(intValue));
		return HxDefaultValue.Default(HxExpr.ENull);
	}

	static function decodeMethodPayload(payload:String, methodBodySrc:Null<String>, methodBodyStart:Int = -1, ?source:String):HxFunctionDecl {
		// Bootstrap note: payload is a `|` separated list (unescaped for '|').
		//
		// v=1:
		//   name|vis|static|args|ret|retstr
		//
		// v=1 (backward-compatible extensions; optional fields):
		//   name|vis|static|args|ret|retstr|retid|argtypes|retexpr
		//
		// Where:
		// - args: comma-separated argument names
		// - retid: first detected `return <ident>` (if any)
		// - argtypes: comma-separated `name:type` pairs (no '|' characters)
		final parts = payload.split("|");
		while (parts.length < 9)
			parts.push("");

		final name = parts[0];
		final vis = parts[1] == "private" ? HxVisibility.Private : HxVisibility.Public;
		final isStatic = parts[2] == "1";

		final argTypes:Map<String, String> = [];
		final optionalArgsByName:Map<String, Bool> = [];
		// Some protocol emitters may preserve the rest marker (`...name`) only in the
		// `argtypes` payload (and not in the raw `args` name list). Track rest names
		// separately so we can still mark `HxFunctionArg.isRest=true` reliably.
		final restArgsByName:Map<String, Bool> = [];
		final argTypesPayload = parts[7];
		if (argTypesPayload.length > 0) {
			for (entry in splitTopLevelComma(argTypesPayload)) {
				if (entry.length == 0)
					continue;
				final idx = entry.indexOf(":");
				if (idx <= 0)
					continue;
				var argName = entry.substr(0, idx);
				// Native parser encodes rest params as `...name`. Normalize for lookup, but also
				// retain the rest marker for later signature building (rest-only functions are
				// common in upstream harness code).
				if (StringTools.startsWith(argName, "...")) {
					argName = argName.substr(3);
					restArgsByName.set(argName, true);
				}
				if (StringTools.startsWith(argName, "?")) {
					argName = argName.substr(1);
					optionalArgsByName.set(argName, true);
				}
				final ty = entry.substr(idx + 1);
				argTypes.set(argName, ty);
			}
		}

		final argsPayload = parts[3];
		final args = new Array<HxFunctionArg>();
		final sourceHints = sourceSignatureArgHints(name, source, methodBodyStart, protocolArgNames(argsPayload));
		if (argsPayload.length > 0) {
			for (a in argsPayload.split(",")) {
				if (a.length == 0)
					continue;
				var rawName = a;
				var isRest = false;
				if (StringTools.startsWith(rawName, "...")) {
					isRest = true;
					rawName = rawName.substr(3);
				}
				var isOptional = false;
				if (StringTools.startsWith(rawName, "?")) {
					isOptional = true;
					rawName = rawName.substr(1);
				}
				if (!isRest && restArgsByName.exists(rawName))
					isRest = true;
				var ty = argTypes.exists(rawName) ? argTypes.get(rawName) : "";
				if (!isOptional && optionalArgsByName.exists(rawName))
					isOptional = true;
				final sourceHint = sourceArgHintByName(sourceHints, rawName);
				var defaultValue = HxDefaultValue.NoDefault;
				var defaultValueText = "";
				if (sourceHint != null) {
					if (sourceHint.isOptional)
						isOptional = true;
					if (sourceArgTypeHintIsMoreSpecific(ty, sourceHint.typeHint))
						ty = sourceHint.typeHint;
					defaultValueText = sourceHint.defaultText;
					defaultValue = defaultValueFromText(defaultValueText);
				}

				if (isRest) {
					// Stage3 bring-up: lower rest args to a single `Array<T>` parameter.
					final inner = (ty == null || StringTools.trim(ty).length == 0) ? "Dynamic" : ty;
					ty = "Array<" + inner + ">";
					isOptional = true;
				}

				args.push(new HxFunctionArg(rawName, ty, defaultValue, isOptional, isRest, defaultValueText));
			}
		}

		final returnTypeHint = normalizeMethodReturnTypeHint(parts[4]);
		final retStr = parts[5];
		final retId = parts[6];
		final retExpr = parts[8];
		final body = new Array<HxStmt>();
		final pos = HxPos.unknown();
		// Prefer the richer `retexpr` field when present (it can represent `Util.ping()`),
		// but keep legacy fields for older protocol emitters.
		if (retExpr.length > 0) {
			body.push(SReturn(parseReturnExprText(retExpr), pos));
		} else if (retStr.length > 0) {
			body.push(SReturn(EString(retStr), pos));
		} else if (retId.length > 0) {
			body.push(SReturn(EIdent(retId), pos));
		}

		var outBody = body;
		#if !hxhx_stage0_no_hx_parser
		if (methodBodySrc != null && methodBodySrc.length > 0) {
			if (Sys.getEnv("HXHX_TRACE_BODY_PARSE_HAVE") == "1") {
				try {
					Sys.println("body_parse_have=" + name + " len=" + methodBodySrc.length);
				} catch (_:haxe.io.Error) {} catch (_:String) {}
			}
			if (Sys.getEnv("HXHX_TRACE_BODY_PARSE_SRC") == "1") {
				try {
					final oneLine = methodBodySrc.split("\n").join("\\n");
					final max = 300;
					final shown = oneLine.length > max ? (oneLine.substr(0, max) + "...") : oneLine;
					Sys.println("body_parse_src=" + name + " " + shown);
				} catch (_:haxe.io.Error) {} catch (_:String) {}
			}
			// Best-effort: recover a structured statement list from the raw source slice.
			//
			// Why
			// - The native frontend protocol v1+ transmits method bodies as raw source
			//   (via `ast method_body`) rather than an OCaml-side statement AST.
			// - Stage3 bring-up wants bodies so it can validate full-body lowering.
			// Debug aid: allow logging parse holes with the method name.
			HxParser.debugBodyLabel = name;
			try {
				outBody = HxParser.parseFunctionBodyTextAt(methodBodySrc, source, methodBodyStart);
			} catch (e:HxParseError) {
				if (Sys.getEnv("HXHX_TRACE_BODY_PARSE_FAIL") == "1") {
					try {
						Sys.println("body_parse_fail=" + name + " err=" + e.message);
					} catch (_:haxe.io.Error) {} catch (_:String) {}
				}
				// Fall back to the summary-only body.
				outBody = body;
			} catch (e:String) {
				if (Sys.getEnv("HXHX_TRACE_BODY_PARSE_FAIL") == "1") {
					try {
						Sys.println("body_parse_fail=" + name + " err=" + e);
					} catch (_:haxe.io.Error) {} catch (_:String) {}
				}
				// Fall back to the summary-only body.
				outBody = body;
			}
			HxParser.debugBodyLabel = "";
		}
		#end

		return new HxFunctionDecl(name, vis, isStatic, args, returnTypeHint, outBody, retStr, null, null, null, methodBodySrc == null ? "" : methodBodySrc);
	}

	static function normalizeMethodReturnTypeHint(typeHint:String):String {
		final text = StringTools.trim(typeHint == null ? "" : typeHint);
		return ~/[\r\n\t ]+untyped$/.replace(text, "");
	}

	static function findFunctionBodyStart(source:String, name:String):Int {
		if (source == null || name == null || name.length == 0)
			return -1;
		final needle = "function " + name;
		var index = source.indexOf(needle);
		while (index >= 0) {
			final afterName = index + needle.length;
			final open = source.indexOf("{", afterName);
			if (open < 0)
				return -1;
			final semi = source.indexOf(";", afterName);
			if (semi < 0 || open < semi)
				return open + 1;
			index = source.indexOf(needle, index + 1);
		}
		return -1;
	}

	static function decodeFieldPayload(payload:String, isFinal:Bool, sourceFieldHints:Map<String, String>):Null<HxFieldDecl> {
		// v=2 field payload (also accepted from v1 `ast static_final`):
		//   name\nvis\nstatic\ntypehint\ninitexpr
		if (payload == null || payload.length == 0)
			return null;
		final lines = payload.split("\n");
		final name = lines.length > 0 ? lines[0] : "";
		if (name.length == 0)
			return null;
		final visLine = lines.length > 1 ? lines[1] : "public";
		final vis = visLine == "private" ? HxVisibility.Private : HxVisibility.Public;
		final isStatic = (lines.length > 2 ? lines[2] : "1") == "1";
		var typeHint = lines.length > 3 ? lines[3] : "";
		final sourceHint = sourceFieldTypeHintByName(sourceFieldHints, name, isStatic);
		if (sourceTypeHintIsMoreSpecific(typeHint, sourceHint))
			typeHint = sourceHint;
		final initRaw = lines.length > 4 ? trimCapturedFieldInitializer(lines.slice(4).join("\n")) : "";
		var init:Null<HxExpr> = null;
		if (initRaw.length > 0)
			init = true ? parseReturnExprText(initRaw) : null;
		return new HxFieldDecl(name, vis, isStatic, typeHint, init, null, null, null, isFinal, "", "", initRaw);
	}

	static function decodeStaticFinalPayload(payload:String, sourceFieldHints:Map<String, String>):Null<HxFieldDecl> {
		return decodeFieldPayload(payload, true, sourceFieldHints);
	}

	static function trimCapturedFieldInitializer(raw:String):String {
		final text = StringTools.trim(raw == null ? "" : raw);
		if (!StringTools.startsWith(text, "switch"))
			return text;
		final end = balancedSwitchEnd(text);
		return end > 0 ? StringTools.trim(text.substr(0, end)) : text;
	}

	static function balancedSwitchEnd(text:String):Int {
		var braceStart = -1;
		for (i in 0...text.length) {
			if (text.charCodeAt(i) == "{".code) {
				braceStart = i;
				break;
			}
		}
		if (braceStart < 0)
			return -1;
		var depth = 0;
		for (i in braceStart...text.length) {
			final c = text.charCodeAt(i);
			if (c == "{".code) {
				depth += 1;
			} else if (c == "}".code) {
				depth -= 1;
				if (depth == 0)
					return i + 1;
			}
		}
		return -1;
	}

	static function stripNewTypeParams(raw:String):String {
		// Bring-up: the native frontend transmits some expression text without fully parsing it.
		//
		// A common upstream pattern is `new Array<T>()` or `new Map<K,V>()`. In plain expression
		// parsing, the `<...>` type-parameter group can be misinterpreted as `<`/`>` operators,
		// producing a structurally valid but semantically nonsense AST (and then invalid OCaml).
		//
		// For Stage3 emission, we do not need to preserve the type parameters, only the allocation
		// shape, so we strip the `<...>` group when it appears immediately after a `new Type`.
		final text = raw == null ? "" : StringTools.trim(raw);
		// The native protocol's expression capture concatenates tokens without spaces, so
		// `new Array<T>()` can arrive as `newArray<T>()`. Normalize that first.
		if (!StringTools.startsWith(text, "new"))
			return text;
		var norm = text;
		if (norm.length > 3) {
			final c3 = norm.charCodeAt(3);
			final isWs = c3 == " ".code || c3 == "\t".code || c3 == "\n".code || c3 == "\r".code;
			if (!isWs)
				norm = "new " + norm.substr(3);
		}
		if (!StringTools.startsWith(norm, "new "))
			return norm;
		final lt = norm.indexOf("<");
		final lp = norm.indexOf("(");
		if (lt < 0 || lp < 0 || lt > lp)
			return text;
		var depth = 0;
		var i = lt;
		while (i < norm.length) {
			final c = norm.charCodeAt(i);
			if (c == "<".code)
				depth++;
			else if (c == ">".code) {
				depth--;
				if (depth == 0) {
					return norm.substr(0, lt) + norm.substr(i + 1);
				}
			}
			i++;
		}
		return norm;
	}

	static function parseReturnExprText(raw:String):HxExpr {
		var exprText = StringTools.trim(raw);
		exprText = stripNewTypeParams(exprText);
		if (exprText.length == 0)
			return EUnsupported("<empty-return-expr>");
		if (looksLikeSwitchCaseFragment(exprText))
			return ENull;

		final regexLiteral = parseRegexLiteral(exprText);
		if (regexLiteral != null)
			return ENew("EReg", [EString(regexLiteral.pattern), EString(regexLiteral.flags)]);

		if (exprText == "null")
			return ENull;
		if (exprText == "true")
			return EBool(true);
		if (exprText == "false")
			return EBool(false);

		if (exprText.length >= 2 && StringTools.startsWith(exprText, "\"") && StringTools.endsWith(exprText, "\"")) {
			return EString(exprText.substr(1, exprText.length - 2));
		}

		// Integers: [-]?[0-9]+ (manual parse to avoid Null<Int> pitfalls in bootstrap output).
		{
			var i = 0;
			var sign = 1;
			if (exprText.length > 0 && exprText.charCodeAt(0) == "-".code) {
				sign = -1;
				i = 1;
			}

			var value = 0;
			var saw = false;
			while (i < exprText.length) {
				final c = exprText.charCodeAt(i);
				if (c < "0".code || c > "9".code) {
					saw = false;
					break;
				}
				saw = true;
				value = value * 10 + (c - "0".code);
				i++;
			}

			if (saw && i == exprText.length)
				return EInt(sign * value);
		}

		// Floats: best-effort via parseFloat if it contains '.'.
		if (exprText.indexOf(".") != -1) {
			final f = Std.parseFloat(exprText);
			if (!Math.isNaN(f))
				return EFloat(f);
		}

		#if hxhx_stage0_no_hx_parser
		// Stage0 profiling lane: avoid pulling the pure-Haxe parser fallback surface.
		return EUnsupported(exprText);
		#else
		// Fallback: try to parse a small field/call chain (e.g. `Util.ping()`).
		var parsed:HxExpr = EUnsupported(exprText);
		try {
			parsed = HxParser.parseExprText(exprText);
		} catch (_:HxParseError) {
			// Last resort: treat as unsupported so emitters don't attempt to print raw Haxe text as OCaml.
			parsed = EUnsupported(exprText);
		} catch (_:String) {
			// Last resort: treat as unsupported so emitters don't attempt to print raw Haxe text as OCaml.
			parsed = EUnsupported(exprText);
		}
		return parsed;
		#end
	}

	static function looksLikeSwitchCaseFragment(exprText:String):Bool {
		// Native return-expression summaries are lossy hints. When OCaml-side
		// token capture starts inside a switch case list, the fragment is not a
		// valid expression and must not poison backend emission as EUnsupported.
		return exprText == "case"
			|| StringTools.startsWith(exprText, "case ")
			|| StringTools.startsWith(exprText, "case\t")
			|| StringTools.startsWith(exprText, "case\n")
			|| exprText == "default"
			|| StringTools.startsWith(exprText, "default:")
			|| StringTools.startsWith(exprText, "default ");
	}

	static function parseRegexLiteral(source:String):Null<{pattern:String, flags:String}> {
		if (!StringTools.startsWith(source, "~/"))
			return null;
		var index = 2;
		var escaped = false;
		while (index < source.length) {
			final code = source.charCodeAt(index);
			if (escaped) {
				escaped = false;
				index++;
				continue;
			}
			if (code == "\\".code) {
				escaped = true;
				index++;
				continue;
			}
			if (code == "/".code) {
				final pattern = source.substr(2, index - 2);
				final flags = source.substr(index + 1);
				var flagIndex = 0;
				while (flagIndex < flags.length) {
					final flagCode = flags.charCodeAt(flagIndex);
					final isLower = flagCode >= "a".code && flagCode <= "z".code;
					final isUpper = flagCode >= "A".code && flagCode <= "Z".code;
					if (!isLower && !isUpper)
						return null;
					flagIndex++;
				}
				return {pattern: pattern, flags: flags};
			}
			index++;
		}
		return null;
	}

	static function throwFromErrLine(line:String):Void {
		// err <index> <line> <col> <len>:<message>
		final parts = splitN(line, 4); // ["err", idx, line, col, tail]
		final idx = parts.length > 1 ? parseDecInt(parts[1]) : -1;
		final ln = parts.length > 2 ? parseDecInt(parts[2]) : -1;
		final col = parts.length > 3 ? parseDecInt(parts[3]) : -1;
		final tail = parts.length > 4 ? parts[4] : "";
		final msg = decodeLenPayload(tail);
		final idx0 = idx < 0 ? 0 : idx;
		final ln0 = ln < 0 ? 0 : ln;
		final col0 = col < 0 ? 0 : col;
		throw "Native frontend: " + msg + " (" + idx0 + ":" + ln0 + ":" + col0 + ")";
	}

	static function decodeLenPayload(s:String):String {
		final colon = s.indexOf(":");
		if (colon <= 0)
			return "";
		final len = parseDecInt(s.substr(0, colon));
		if (len < 0)
			return "";
		final payload = s.substr(colon + 1);
		final raw = payload.substr(0, len);
		return unescapePayload(raw);
	}

	static function parseDecInt(s:String):Int {
		if (s == null)
			return -1;
		var i = 0;
		// Trim leading spaces (defensive).
		while (i < s.length && s.charCodeAt(i) == " ".code)
			i++;
		if (i >= s.length)
			return -1;
		var value = 0;
		var saw = false;
		while (i < s.length) {
			final c = s.charCodeAt(i);
			if (c < "0".code || c > "9".code)
				break;
			saw = true;
			value = value * 10 + (c - "0".code);
			i++;
		}
		return saw ? value : -1;
	}

	static function unescapePayload(s:String):String {
		final out = new StringBuf();
		var i = 0;
		while (i < s.length) {
			final c = s.charCodeAt(i);
			if (c == "\\".code && i + 1 < s.length) {
				final n = s.charCodeAt(i + 1);
				switch (n) {
					case "n".code:
						out.addChar("\n".code);
					case "r".code:
						out.addChar("\r".code);
					case "t".code:
						out.addChar("\t".code);
					case "\\".code:
						out.addChar("\\".code);
					case _:
						out.addChar(n);
				}
				i += 2;
				continue;
			}
			out.addChar(c);
			i++;
		}
		return out.toString();
	}

	static function splitN(s:String, n:Int):Array<String> {
		// Split into exactly `n` space-separated fields, plus a final "tail" field (may contain spaces).
		final head = new Array<String>();
		var i = 0;
		var start = 0;
		while (head.length < n && i <= s.length) {
			if (i == s.length || s.charCodeAt(i) == " ".code) {
				if (i > start)
					head.push(s.substr(start, i - start));
				while (i < s.length && s.charCodeAt(i) == " ".code)
					i++;
				start = i;
				continue;
			}
			i++;
		}
		while (head.length < n)
			head.push("");
		final tail = start <= s.length ? s.substr(start) : "";
		head.push(tail);
		return head;
	}
}
