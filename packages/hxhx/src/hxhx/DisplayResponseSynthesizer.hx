package hxhx;

import haxe.io.Bytes;

private typedef DisplayRequestQuery = {
	final sourcePath:String;
	final cursorOffset:Int;
	final mode:String;
};

private typedef DisplayToken = {
	final text:String;
	final start:Int;
	final end:Int;
	final isIdent:Bool;
};

/**
	Display response synthesizer for Stage3 bring-up.

	Why
	- Stage3 still uses synthetic display responses for most modes.
	- For day-to-day macro API authoring, we want one higher-value completion path:
	  when cursor is inside an object literal passed to a macro argument typed as `ExprOf<T>`,
	  suggest the fields from `T` when `T` is an anonymous typedef.

	What
	- Keeps existing synthetic mode responses (`@diagnostics`, `@type`, etc.).
	- Adds a focused completion path for `ExprOf<T>` object-literal arguments.

	How
	- Parse `--display <path@pos[@mode]>`.
	- Resolve source from `display-stdin` payload (or fallback file path).
	- Tokenize source (comment/string aware), identify current call arg, resolve function arg type hint,
	  extract `ExprOf<T>`, read typedef fields, and emit an XML completion list.
**/
class DisplayResponseSynthesizer {
	static function parseStrictInt(text:String):Int {
		if (text == null) return -1;
		final trimmed = StringTools.trim(text);
		if (trimmed.length == 0) return -1;

		var start = 0;
		if (trimmed.charCodeAt(0) == "-".code) {
			if (trimmed.length == 1) return -1;
			start = 1;
		}

		for (index in start...trimmed.length) {
			final code = trimmed.charCodeAt(index);
			if (code < "0".code || code > "9".code) return -1;
		}

		final parsed = Std.parseInt(trimmed);
		return parsed == null ? -1 : parsed;
	}

	static function parseDisplayRequestQuery(displayRequest:String):DisplayRequestQuery {
		if (displayRequest == null) return { sourcePath: "", cursorOffset: -1, mode: "" };

		final trimmed = StringTools.trim(displayRequest);
		if (trimmed.length == 0) return { sourcePath: "", cursorOffset: -1, mode: "" };

		final at = trimmed.indexOf("@");
		if (at == -1) return { sourcePath: trimmed, cursorOffset: -1, mode: "" };

		final sourcePath = trimmed.substr(0, at);
		final tail = trimmed.substr(at + 1);
		final secondAt = tail.indexOf("@");

		var cursorOffset = -1;
		var mode = "";
		if (secondAt == -1) {
			final cursor = parseStrictInt(tail);
			if (cursor >= 0) cursorOffset = cursor; else mode = tail;
		} else {
			final cursorText = tail.substr(0, secondAt);
			final cursor = parseStrictInt(cursorText);
			if (cursor >= 0) {
				cursorOffset = cursor;
				mode = tail.substr(secondAt + 1);
			} else {
				mode = tail;
			}
		}

		return {
			sourcePath: sourcePath,
			cursorOffset: cursorOffset,
			mode: mode
		};
	}

	public static function readDisplaySource(displayRequest:String, stdinBytes:Null<Bytes>):String {
		final query = parseDisplayRequestQuery(displayRequest);
		if (stdinBytes != null && stdinBytes.length > 0) {
			return stdinBytes.getString(0, stdinBytes.length);
		}

		if (query.sourcePath == null || query.sourcePath.length == 0) return "";
		if (!sys.FileSystem.exists(query.sourcePath)) return "";
		if (sys.FileSystem.isDirectory(query.sourcePath)) return "";
		return try {
			sys.io.File.getContent(query.sourcePath);
		} catch (_:Dynamic) {
			"";
		}
	}

	static inline function isIdentStart(code:Int):Bool {
		return (code >= "A".code && code <= "Z".code) || (code >= "a".code && code <= "z".code) || code == "_".code;
	}

	static inline function isIdentContinue(code:Int):Bool {
		return isIdentStart(code) || (code >= "0".code && code <= "9".code);
	}

	static function tokenizeDisplaySource(source:String):Array<DisplayToken> {
		final out = new Array<DisplayToken>();
		if (source == null || source.length == 0) return out;

		var index = 0;
		while (index < source.length) {
			final code = source.charCodeAt(index);

			if (code == " ".code || code == "\t".code || code == "\r".code || code == "\n".code) {
				index += 1;
				continue;
			}

			if (code == "/".code && index + 1 < source.length && source.charCodeAt(index + 1) == "/".code) {
				index += 2;
				while (index < source.length && source.charCodeAt(index) != "\n".code) index += 1;
				continue;
			}

			if (code == "/".code && index + 1 < source.length && source.charCodeAt(index + 1) == "*".code) {
				index += 2;
				while (index + 1 < source.length) {
					if (source.charCodeAt(index) == "*".code && source.charCodeAt(index + 1) == "/".code) {
						index += 2;
						break;
					}
					index += 1;
				}
				continue;
			}

			if (code == "\"".code || code == "'".code) {
				final quote = code;
				final start = index;
				index += 1;
				while (index < source.length) {
					final current = source.charCodeAt(index);
					if (current == "\\".code) {
						index += 2;
						continue;
					}
					index += 1;
					if (current == quote) break;
				}
				out.push({
					text: source.substr(start, index - start),
					start: start,
					end: index,
					isIdent: false
				});
				continue;
			}

			if (isIdentStart(code)) {
				final start = index;
				index += 1;
				while (index < source.length && isIdentContinue(source.charCodeAt(index))) index += 1;
				out.push({
					text: source.substr(start, index - start),
					start: start,
					end: index,
					isIdent: true
				});
				continue;
			}

			out.push({
				text: String.fromCharCode(code),
				start: index,
				end: index + 1,
				isIdent: false
			});
			index += 1;
		}

		return out;
	}

	static function findMatchingCloseToken(tokens:Array<DisplayToken>, openIndex:Int, openSymbol:String, closeSymbol:String):Int {
		if (tokens == null || openIndex < 0 || openIndex >= tokens.length) return -1;
		var depth = 0;
		for (tokenIndex in openIndex...tokens.length) {
			final token = tokens[tokenIndex];
			if (token.text == openSymbol) {
				depth += 1;
			} else if (token.text == closeSymbol) {
				depth -= 1;
				if (depth == 0) return tokenIndex;
			}
		}
		return -1;
	}

	static function countArgumentIndexBeforeToken(tokens:Array<DisplayToken>, openParenIndex:Int, boundaryIndex:Int):Int {
		var depthParen = 0;
		var depthBrace = 0;
		var depthBracket = 0;
		var depthAngle = 0;
		var argumentIndex = 0;

		for (tokenIndex in (openParenIndex + 1)...boundaryIndex) {
			final token = tokens[tokenIndex];
			final text = token.text;

			switch (text) {
				case "(":
					depthParen += 1;
				case ")":
					if (depthParen > 0) depthParen -= 1;
				case "{":
					depthBrace += 1;
				case "}":
					if (depthBrace > 0) depthBrace -= 1;
				case "[":
					depthBracket += 1;
				case "]":
					if (depthBracket > 0) depthBracket -= 1;
				case "<":
					depthAngle += 1;
				case ">":
					if (depthAngle > 0) depthAngle -= 1;
				case ",":
					if (depthParen == 0 && depthBrace == 0 && depthBracket == 0 && depthAngle == 0) {
						argumentIndex += 1;
					}
				case _:
			}
		}

		return argumentIndex;
	}

	static function findCallNameBeforeParen(tokens:Array<DisplayToken>, openParenIndex:Int):String {
		var tokenIndex = openParenIndex - 1;
		while (tokenIndex >= 0) {
			final token = tokens[tokenIndex];
			if (token.isIdent) return token.text;
			if (token.text == ")" || token.text == "}" || token.text == "]") return "";
			tokenIndex -= 1;
		}
		return "";
	}

	static function extractArgTypeHintFromSegment(source:String, tokens:Array<DisplayToken>, segmentStart:Int, segmentEnd:Int):String {
		if (segmentStart >= segmentEnd) return "";

		var depthParen = 0;
		var depthBrace = 0;
		var depthBracket = 0;
		var depthAngle = 0;
		var colonIndex = -1;
		for (tokenIndex in segmentStart...segmentEnd) {
			final token = tokens[tokenIndex];
			switch (token.text) {
				case "(":
					depthParen += 1;
				case ")":
					if (depthParen > 0) depthParen -= 1;
				case "{":
					depthBrace += 1;
				case "}":
					if (depthBrace > 0) depthBrace -= 1;
				case "[":
					depthBracket += 1;
				case "]":
					if (depthBracket > 0) depthBracket -= 1;
				case "<":
					depthAngle += 1;
				case ">":
					if (depthAngle > 0) depthAngle -= 1;
				case ":":
					if (depthParen == 0 && depthBrace == 0 && depthBracket == 0 && depthAngle == 0) {
						colonIndex = tokenIndex;
						break;
					}
				case _:
			}
			if (colonIndex >= 0) break;
		}

		if (colonIndex < 0 || colonIndex + 1 >= segmentEnd) return "";
		final typeStartIndex = colonIndex + 1;

		depthParen = 0;
		depthBrace = 0;
		depthBracket = 0;
		depthAngle = 0;
		var typeEndIndex = segmentEnd;
		for (tokenIndex in typeStartIndex...segmentEnd) {
			final token = tokens[tokenIndex];
			switch (token.text) {
				case "(":
					depthParen += 1;
				case ")":
					if (depthParen > 0) depthParen -= 1;
				case "{":
					depthBrace += 1;
				case "}":
					if (depthBrace > 0) depthBrace -= 1;
				case "[":
					depthBracket += 1;
				case "]":
					if (depthBracket > 0) depthBracket -= 1;
				case "<":
					depthAngle += 1;
				case ">":
					if (depthAngle > 0) depthAngle -= 1;
				case "=":
					if (depthParen == 0 && depthBrace == 0 && depthBracket == 0 && depthAngle == 0) {
						typeEndIndex = tokenIndex;
						break;
					}
				case _:
			}
			if (typeEndIndex != segmentEnd) break;
		}

		if (typeStartIndex >= typeEndIndex) return "";
		final startPos = tokens[typeStartIndex].start;
		final endPos = tokens[typeEndIndex - 1].end;
		if (startPos < 0 || endPos <= startPos || endPos > source.length) return "";
		return StringTools.trim(source.substr(startPos, endPos - startPos));
	}

	static function findFunctionArgTypeHint(source:String, tokens:Array<DisplayToken>, functionName:String, argumentIndex:Int):String {
		if (functionName == null || functionName.length == 0 || argumentIndex < 0) return "";

		for (tokenIndex in 0...tokens.length) {
			if (!tokens[tokenIndex].isIdent || tokens[tokenIndex].text != "function") continue;

			var nameIndex = tokenIndex + 1;
			while (nameIndex < tokens.length && !tokens[nameIndex].isIdent) nameIndex += 1;
			if (nameIndex >= tokens.length) continue;
			if (tokens[nameIndex].text != functionName) continue;

			var openParenIndex = nameIndex + 1;
			while (openParenIndex < tokens.length && tokens[openParenIndex].text != "(") openParenIndex += 1;
			if (openParenIndex >= tokens.length) continue;

			final closeParenIndex = findMatchingCloseToken(tokens, openParenIndex, "(", ")");
			if (closeParenIndex < 0) continue;

			var depthParen = 0;
			var depthBrace = 0;
			var depthBracket = 0;
			var depthAngle = 0;
			var currentArgument = 0;
			var segmentStart = openParenIndex + 1;
			var foundSegmentStart = -1;
			var foundSegmentEnd = -1;

			for (segmentIndex in (openParenIndex + 1)...(closeParenIndex + 1)) {
				final boundary = segmentIndex == closeParenIndex;
				final token = boundary ? null : tokens[segmentIndex];
				final atTopLevelComma = !boundary
					&& token.text == ","
					&& depthParen == 0
					&& depthBrace == 0
					&& depthBracket == 0
					&& depthAngle == 0;

				if (boundary || atTopLevelComma) {
					if (currentArgument == argumentIndex) {
						foundSegmentStart = segmentStart;
						foundSegmentEnd = segmentIndex;
						break;
					}
					currentArgument += 1;
					segmentStart = segmentIndex + 1;
					continue;
				}

				switch (token.text) {
					case "(":
						depthParen += 1;
					case ")":
						if (depthParen > 0) depthParen -= 1;
					case "{":
						depthBrace += 1;
					case "}":
						if (depthBrace > 0) depthBrace -= 1;
					case "[":
						depthBracket += 1;
					case "]":
						if (depthBracket > 0) depthBracket -= 1;
					case "<":
						depthAngle += 1;
					case ">":
						if (depthAngle > 0) depthAngle -= 1;
					case _:
				}
			}

			if (foundSegmentStart >= 0 && foundSegmentEnd > foundSegmentStart) {
				return extractArgTypeHintFromSegment(source, tokens, foundSegmentStart, foundSegmentEnd);
			}
		}

		return "";
	}

	static function compactWhitespace(text:String):String {
		if (text == null || text.length == 0) return "";
		final out = new StringBuf();
		for (index in 0...text.length) {
			final code = text.charCodeAt(index);
			if (code == " ".code || code == "\t".code || code == "\r".code || code == "\n".code) continue;
			out.addChar(code);
		}
		return out.toString();
	}

	static function extractExprOfInner(typeHint:String):String {
		final compact = compactWhitespace(typeHint);
		if (compact.length == 0) return "";

		final marker = "ExprOf<";
		final markerIndex = compact.indexOf(marker);
		if (markerIndex < 0) return "";

		final innerStart = markerIndex + marker.length;
		var depth = 1;
		for (index in innerStart...compact.length) {
			final code = compact.charCodeAt(index);
			if (code == "<".code) {
				depth += 1;
			} else if (code == ">".code) {
				depth -= 1;
				if (depth == 0) return compact.substr(innerStart, index - innerStart);
			}
		}

		return "";
	}

	static function parseStructFieldNames(structBody:String):Array<String> {
		final fields = new Array<String>();
		final seen:Map<String, Bool> = new Map();
		final tokens = tokenizeDisplaySource(structBody);
		if (tokens.length == 0) return fields;

		var depthParen = 0;
		var depthBrace = 0;
		var depthBracket = 0;
		var depthAngle = 0;
		var tokenIndex = 0;
		while (tokenIndex < tokens.length) {
			final token = tokens[tokenIndex];
			final atTopLevel = depthParen == 0 && depthBrace == 0 && depthBracket == 0 && depthAngle == 0;
			if (atTopLevel) {
				var nameIndex = tokenIndex;
				if (token.text == "?") nameIndex += 1;
				if (nameIndex < tokens.length && tokens[nameIndex].isIdent) {
					final nameToken = tokens[nameIndex];
					final colonIndex = nameIndex + 1;
					if (colonIndex < tokens.length && tokens[colonIndex].text == ":" && !seen.exists(nameToken.text)) {
						seen.set(nameToken.text, true);
						fields.push(nameToken.text);
					}
				}
			}

			switch (token.text) {
				case "(":
					depthParen += 1;
				case ")":
					if (depthParen > 0) depthParen -= 1;
				case "{":
					depthBrace += 1;
				case "}":
					if (depthBrace > 0) depthBrace -= 1;
				case "[":
					depthBracket += 1;
				case "]":
					if (depthBracket > 0) depthBracket -= 1;
				case "<":
					depthAngle += 1;
				case ">":
					if (depthAngle > 0) depthAngle -= 1;
				case _:
			}

			tokenIndex += 1;
		}

		return fields;
	}

	static function stripTypePath(typePath:String):String {
		if (typePath == null || typePath.length == 0) return "";
		final compact = compactWhitespace(typePath);
		final dotIndex = compact.lastIndexOf(".");
		return dotIndex < 0 ? compact : compact.substr(dotIndex + 1);
	}

	static function findTypedefStructBody(source:String, tokens:Array<DisplayToken>, typeName:String):String {
		final simpleName = stripTypePath(typeName);
		if (simpleName.length == 0) return "";

		for (tokenIndex in 0...tokens.length) {
			final token = tokens[tokenIndex];
			if (!token.isIdent || token.text != "typedef") continue;

			var nameIndex = tokenIndex + 1;
			while (nameIndex < tokens.length && !tokens[nameIndex].isIdent) nameIndex += 1;
			if (nameIndex >= tokens.length) continue;
			if (tokens[nameIndex].text != simpleName) continue;

			var equalsIndex = nameIndex + 1;
			while (equalsIndex < tokens.length && tokens[equalsIndex].text != "=") equalsIndex += 1;
			if (equalsIndex >= tokens.length) continue;

			var braceIndex = equalsIndex + 1;
			while (braceIndex < tokens.length && tokens[braceIndex].text != "{") braceIndex += 1;
			if (braceIndex >= tokens.length) continue;

			final closeBraceIndex = findMatchingCloseToken(tokens, braceIndex, "{", "}");
			if (closeBraceIndex < 0) continue;

			final startPos = tokens[braceIndex].end;
			final endPos = tokens[closeBraceIndex].start;
			if (endPos <= startPos || endPos > source.length) continue;
			return source.substr(startPos, endPos - startPos);
		}

		return "";
	}

	static function xmlEscape(text:String):String {
		if (text == null || text.length == 0) return "";
		var out = StringTools.replace(text, "&", "&amp;");
		out = StringTools.replace(out, "<", "&lt;");
		out = StringTools.replace(out, ">", "&gt;");
		out = StringTools.replace(out, "\"", "&quot;");
		return out;
	}

	static function formatCompletionList(fields:Array<String>):String {
		if (fields == null || fields.length == 0) return "<list></list>";
		final out = new StringBuf();
		out.add("<list>");
		for (field in fields) out.add('<i n="' + xmlEscape(field) + '"/>');
		out.add("</list>");
		return out.toString();
	}

	static function synthesizeExprOfStructCompletion(displayRequest:String, displaySource:String):String {
		final query = parseDisplayRequestQuery(displayRequest);
		if (query.cursorOffset < 0) return "";
		final mode = query.mode == null ? "" : query.mode;
		if (mode.length > 0) return "";

		final source = displaySource == null ? "" : displaySource;
		if (source.length == 0) return "";

		final tokens = tokenizeDisplaySource(source);
		if (tokens.length == 0) return "";

		final stack = new Array<{symbol:String, tokenIndex:Int}>();
		for (tokenIndex in 0...tokens.length) {
			final token = tokens[tokenIndex];
			if (token.start >= query.cursorOffset) break;
			switch (token.text) {
				case "(", "{", "[":
					stack.push({ symbol: token.text, tokenIndex: tokenIndex });
				case ")":
					if (stack.length > 0 && stack[stack.length - 1].symbol == "(") stack.pop();
				case "}":
					if (stack.length > 0 && stack[stack.length - 1].symbol == "{") stack.pop();
				case "]":
					if (stack.length > 0 && stack[stack.length - 1].symbol == "[") stack.pop();
				case _:
			}
		}

		var braceTokenIndex = -1;
		var parenTokenIndex = -1;
		for (stackIndex in 0...stack.length) {
			final frame = stack[stack.length - 1 - stackIndex];
			if (braceTokenIndex < 0 && frame.symbol == "{") {
				braceTokenIndex = frame.tokenIndex;
				continue;
			}
			if (braceTokenIndex >= 0 && frame.symbol == "(" && frame.tokenIndex < braceTokenIndex) {
				parenTokenIndex = frame.tokenIndex;
				break;
			}
		}

		if (braceTokenIndex < 0 || parenTokenIndex < 0) return "";

		final functionName = findCallNameBeforeParen(tokens, parenTokenIndex);
		if (functionName.length == 0) return "";

		final argumentIndex = countArgumentIndexBeforeToken(tokens, parenTokenIndex, braceTokenIndex);
		final argTypeHint = findFunctionArgTypeHint(source, tokens, functionName, argumentIndex);
		if (argTypeHint.length == 0) return "";

		final exprOfInner = extractExprOfInner(argTypeHint);
		if (exprOfInner.length == 0) return "";

		var structBody = "";
		if (StringTools.startsWith(exprOfInner, "{") && StringTools.endsWith(exprOfInner, "}")) {
			structBody = exprOfInner.substr(1, exprOfInner.length - 2);
		} else {
			structBody = findTypedefStructBody(source, tokens, exprOfInner);
		}
		if (structBody.length == 0) return "";

		final fields = parseStructFieldNames(structBody);
		if (fields.length == 0) return "";
		return formatCompletionList(fields);
	}

	public static function synthesize(displayRequest:String, displaySource:String):String {
		final exprOfCompletion = synthesizeExprOfStructCompletion(displayRequest, displaySource);
		if (exprOfCompletion.length > 0) return exprOfCompletion;

		final req = displayRequest == null ? "" : displayRequest;
		if (StringTools.endsWith(req, "@diagnostics")) return "[{\"diagnostics\":[]}]";
		if (StringTools.endsWith(req, "@module-symbols")) return "[{\"symbols\":[]}]";
		if (StringTools.endsWith(req, "@signature")) return "{\"signatures\":[],\"activeSignature\":0,\"activeParameter\":0}";
		if (StringTools.endsWith(req, "@toplevel")) return "<il></il>";
		if (StringTools.endsWith(req, "@type")) return "<type>Dynamic</type>";
		if (StringTools.endsWith(req, "@position")) return "<list></list>";
		if (StringTools.endsWith(req, "@usage")) return "<list></list>";
		return "<list></list>";
	}
}
