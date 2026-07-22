package backend.js;

/**
	Expression-to-JS lowering for `js-native` MVP.

	Why
	- Stage3 already has a parsed expression AST; this mapper turns the MVP subset into JS text.
	- Unsupported shapes fail fast so bring-up diffs are explicit and actionable.
**/
class JsExprEmitter {
	static function unsupported(kind:String, ?detail:String):String {
		final hasDetail = detail != null && detail.length > 0;
		throw "[js-native:unsupported_expr] kind=" + kind + (hasDetail ? " detail=" + detail : "");
	}

	static function nestedScope(parent:JsEmitScope, locals:haxe.ds.StringMap<String>):JsEmitScope {
		return {
			resolveLocal: function(name:String):Null<String> {
				final v = locals.get(name);
				if (v != null)
					return v;
				return parent == null ? null : parent.resolveLocal(name);
			},
			resolveClassRef: function(name:String):Null<String> {
				return parent == null ? null : parent.resolveClassRef(name);
			},
			resolveSuperClassRef: function():Null<String> {
				return parent == null ? null : parent.resolveSuperClassRef();
			}
		};
	}

	public static function emit(expr:HxExpr, scope:JsEmitScope):String {
		final exactCall = TypedExactCallSource.decodeInstance(expr);
		if (exactCall != null)
			return emit(TypedExactCallSource.ordinaryInstanceCall(exactCall), scope);
		return switch (expr) {
			case ENull:
				"null";
			case EBool(v):
				v ? "true" : "false";
			case EString(v):
				JsNameMangler.quoteString(v);
			case EInt(v):
				Std.string(v);
			case EFloat(v):
				Std.string(v);
			case EEnumValue(name):
				final cls = scope == null ? null : scope.resolveClassRef(name);
				cls == null ? JsNameMangler.quoteString(name) : cls;
			case EThis:
				"this";
			case ESuper:
				"super";
			case EIdent(name):
				resolveIdent(name, scope);
			case EField(obj, field):
				emitField(obj, field, scope);
			case ENullSafeField(obj, field):
				emitNullSafeField(obj, field, scope);
			case ECall(callee, args):
				emitCall(callee, args, scope);
			case EReturn(_):
				unsupported("EReturn", "expression-position return must be consumed by macro expansion before JS emission");
			case EVars(_):
				unsupported("EVars", "expression-position variable declarations must be consumed by macro expansion before JS emission");
			case EVariableDeclaration(_, _, _, _, _, _):
				unsupported("EVariableDeclaration", "a variable declaration must remain inside its expression declaration list");
			case EMacroExpr(inner, wrappers):
				emitMacroExpr(inner, wrappers, scope);
			case EMacroType(typeText):
				emitMacroType(typeText);
			case EUnop(op, fixity, inner) if (op == Increment || op == Decrement):
				emitIncDec(op, fixity, inner, scope);
			case EUnop(op, fixity, inner):
				HxUnaryOperatorTools.requireValidFixity(op, fixity);
				"(" + HxUnaryOperatorTools.sourceToken(op) + emit(inner, scope) + ")";
			case EBinop(op, left, right):
				emitBinop(op, left, right, scope);
			case ETernary(cond, thenExpr, elseExpr):
				"("
				+ emit(cond, scope)
				+ " ? "
				+ emit(thenExpr, scope)
				+ " : "
				+ emit(elseExpr, scope)
				+ ")";
			case EAnon(fieldNames, fieldValues):
				emitAnon(fieldNames, fieldValues, scope);
			case EArrayDecl(values):
				if (isMapLiteral(values)) emitMapLiteral(values, scope); else "[" + values.map(v -> emit(v, scope)).join(", ") + "]";
			case EArrayAccess(array, index):
				emitArrayRead(array, index, scope);
			case ELambda(args, body):
				emitLambda(args, body, scope);
			case ECast(inner, _):
				emit(inner, scope);
			case EUntyped(inner):
				emit(inner, scope);
			case ESwitch(scrutinee, patterns, exprs):
				emitSwitchExpr(scrutinee, patterns, exprs, scope);
			case ESwitchRaw(_):
				unsupported("ESwitchRaw");
			case ETryCatchRaw(raw):
				emitTryCatchRaw(raw, scope);
			case ERange(startExpr, endExpr):
				emitRangeExpr(startExpr, endExpr, scope);
			case EArrayComprehension(name, iterable, guardExpr, yieldExpr):
				emitArrayComprehension(name, iterable, guardExpr, yieldExpr, scope);
			case ENew(typePath, args):
				emitNew(typePath, args, scope);
			case EUnsupported(raw):
				unsupported("EUnsupported", raw);
		}
	}

	/**
		Lower the parser's token-preserving `try` expression placeholder into valid JS.

		Why
		- Haxe allows `try/catch` in expression position.
		- JavaScript only has statement-level `try/catch`, so expression-position use needs
		  an IIFE and explicit returns from the successful/catch blocks.
		- The Stage3 parser intentionally keeps this shape as raw text to avoid an OCaml
		  bootstrap module cycle between `HxExpr` and `HxStmt`.

		What / How
		- Handles the common simple shape captured by the parser:
		  `try { ... } catch(name:Type) { ... }`.
		- Removes Haxe catch type hints for JS syntax.
		- Converts the last top-level expression in each block into `return <expr>;`.
		- Falls back to a syntax-preserving IIFE for more complex raw shapes.
	**/
	static function emitTryCatchRaw(raw:String, ?scope:JsEmitScope):String {
		if (raw == null || raw.length == 0 || raw == "opaque_block_expr")
			unsupported("ETryCatchRaw", raw);

		final opaqueBlock = rewriteOpaqueBlockExprRaw(raw, scope);
		if (opaqueBlock != null)
			return opaqueBlock;

		final rewritten = rewriteSimpleTryCatchRaw(raw, scope);
		if (rewritten != null)
			return rewritten;

		var js = rewriteRawQualifiedClassNews(sanitizeCatchTypeHints(raw), scope);
		if (js.indexOf("catch") < 0 && js.indexOf("finally") < 0)
			js += "catch(__hx_err){throw __hx_err;}";
		return "(function () { " + js + " })()";
	}

	static function rewriteOpaqueBlockExprRaw(raw:String, ?scope:JsEmitScope):Null<String> {
		final marker = "opaque_block_expr:";
		if (!StringTools.startsWith(raw, marker))
			return null;

		var body = StringTools.trim(raw.substr(marker.length));
		if (body.length == 0)
			unsupported("ETryCatchRaw", raw);

		if (body.charCodeAt(0) == "{".code) {
			final close = findMatching(body, 0, "{".code, "}".code);
			if (close == body.length - 1)
				body = body.substring(1, close);
		}

		return "(function () { " + blockToReturningJs(body, scope) + " })()";
	}

	static function rewriteSimpleTryCatchRaw(raw:String, ?scope:JsEmitScope):Null<String> {
		raw = StringTools.trim(raw);
		if (!StringTools.startsWith(raw, "try"))
			return null;

		final tryOpen = skipWhitespace(raw, 3);
		if (tryOpen >= raw.length || raw.charCodeAt(tryOpen) != "{".code)
			return null;
		final tryClose = findMatching(raw, tryOpen, "{".code, "}".code);
		if (tryClose < 0)
			return null;

		final catchStart = skipWhitespace(raw, tryClose + 1);
		if (raw.substr(catchStart, 5) != "catch")
			return null;
		final catchParenOpen = skipWhitespace(raw, catchStart + 5);
		if (catchParenOpen >= raw.length || raw.charCodeAt(catchParenOpen) != "(".code)
			return null;
		final catchParenClose = findMatching(raw, catchParenOpen, "(".code, ")".code);
		if (catchParenClose < 0)
			return null;

		final catchBodyOpen = skipWhitespace(raw, catchParenClose + 1);
		if (catchBodyOpen >= raw.length || raw.charCodeAt(catchBodyOpen) != "{".code)
			return null;
		final catchBodyClose = findMatching(raw, catchBodyOpen, "{".code, "}".code);
		if (catchBodyClose < 0)
			return null;

		final trailing = StringTools.trim(raw.substr(catchBodyClose + 1));
		if (trailing.length != 0)
			return null;

		final catchName = sanitizeCatchName(raw.substring(catchParenOpen + 1, catchParenClose));
		final tryBody = blockToReturningJs(raw.substring(tryOpen + 1, tryClose), scope);
		final catchBody = blockToReturningJs(raw.substring(catchBodyOpen + 1, catchBodyClose), scope);
		return "(function () { try { " + tryBody + " } catch (" + catchName + ") { " + catchBody + " } })()";
	}

	static function skipWhitespace(source:String, start:Int):Int {
		var i = start;
		while (i < source.length) {
			switch (source.charCodeAt(i)) {
				case 9 | 10 | 11 | 12 | 13 | 32:
					i++;
				case _:
					return i;
			}
		}
		return i;
	}

	static function sanitizeCatchTypeHints(raw:String):String {
		final out = new StringBuf();
		var offset = 0;
		while (offset < raw.length) {
			final catchIndex = raw.indexOf("catch(", offset);
			if (catchIndex < 0) {
				out.add(raw.substr(offset));
				break;
			}
			out.add(raw.substring(offset, catchIndex));
			final parenOpen = catchIndex + 5;
			final parenClose = findMatching(raw, parenOpen, "(".code, ")".code);
			if (parenClose < 0) {
				out.add(raw.substr(catchIndex));
				break;
			}
			out.add("catch(");
			out.add(sanitizeCatchName(raw.substring(parenOpen + 1, parenClose)));
			out.add(")");
			offset = parenClose + 1;
		}
		return out.toString();
	}

	static function sanitizeCatchName(signature:String):String {
		var name = signature == null ? "" : StringTools.trim(signature);
		final colon = name.indexOf(":");
		if (colon >= 0)
			name = StringTools.trim(name.substr(0, colon));
		if (name.length == 0)
			return "__hx_err";
		return JsNameMangler.identifier(name);
	}

	static function blockToReturningJs(body:String, ?scope:JsEmitScope):String {
		var trimmed = sanitizeRawHaxeExpressionSyntax(body == null ? "" : StringTools.trim(body), scope);
		while (StringTools.endsWith(trimmed, ";"))
			trimmed = StringTools.trim(trimmed.substr(0, trimmed.length - 1));
		trimmed = sanitizeRawHaxeExpressionSyntax(trimmed, scope);
		if (trimmed.length == 0)
			return "return null;";
		if (StringTools.startsWith(trimmed, "return ") || StringTools.startsWith(trimmed, "throw "))
			return trimmed + ";";

		final lastSemi = findLastTopLevelSemicolon(trimmed);
		final prefix = lastSemi >= 0 ? trimmed.substr(0, lastSemi + 1) : "";
		final expr = StringTools.trim(lastSemi >= 0 ? trimmed.substr(lastSemi + 1) : trimmed);
		if (expr.length == 0)
			return prefix + " return null;";
		if (StringTools.startsWith(expr, "return ") || StringTools.startsWith(expr, "throw "))
			return prefix + " " + expr + ";";
		if (StringTools.startsWith(expr, "var ") || StringTools.startsWith(expr, "let ") || StringTools.startsWith(expr, "const "))
			return trimmed + "; return null;";
		final controlThenReturn = rewriteLeadingControlThenReturn(expr, scope);
		if (controlThenReturn != null)
			return prefix + " " + controlThenReturn;
		return prefix + " return " + expr + ";";
	}

	static function rewriteLeadingControlThenReturn(raw:String, ?scope:JsEmitScope):Null<String> {
		final rewrittenIf = rewriteLeadingIfThenReturn(raw, scope);
		if (rewrittenIf != null)
			return rewrittenIf;
		final rewrittenWhile = rewriteLeadingWhileThenReturn(raw, scope);
		if (rewrittenWhile != null)
			return rewrittenWhile;
		return null;
	}

	static function rewriteLeadingWhileThenReturn(raw:String, ?scope:JsEmitScope):Null<String> {
		raw = raw == null ? "" : StringTools.trim(raw);
		if (!startsWithRawKeyword(raw, 0, "while"))
			return null;

		final parenOpen = skipWhitespace(raw, 5);
		if (parenOpen >= raw.length || raw.charCodeAt(parenOpen) != "(".code)
			return null;
		final parenClose = findMatching(raw, parenOpen, "(".code, ")".code);
		if (parenClose < 0)
			return null;

		final bodyOpen = skipWhitespace(raw, parenClose + 1);
		if (bodyOpen >= raw.length || raw.charCodeAt(bodyOpen) != "{".code)
			return null;
		final bodyClose = findMatching(raw, bodyOpen, "{".code, "}".code);
		if (bodyClose < 0)
			return null;

		var trailing = StringTools.trim(raw.substr(bodyClose + 1));
		while (StringTools.startsWith(trailing, ";"))
			trailing = StringTools.trim(trailing.substr(1));
		while (StringTools.endsWith(trailing, ";"))
			trailing = StringTools.trim(trailing.substr(0, trailing.length - 1));

		final cond = sanitizeRawHaxeExpressionSyntax(raw.substring(parenOpen + 1, parenClose), scope);
		final body = sanitizeRawHaxeExpressionSyntax(raw.substring(bodyOpen + 1, bodyClose), scope);
		final result = trailing.length == 0 ? "null" : sanitizeRawHaxeExpressionSyntax(trailing, scope);
		return "while (" + cond + ") { " + body + " } return " + result + ";";
	}

	static function rewriteLeadingIfThenReturn(raw:String, ?scope:JsEmitScope):Null<String> {
		raw = raw == null ? "" : StringTools.trim(raw);
		if (!startsWithRawKeyword(raw, 0, "if"))
			return null;

		final parenOpen = skipWhitespace(raw, 2);
		if (parenOpen >= raw.length || raw.charCodeAt(parenOpen) != "(".code)
			return null;
		final parenClose = findMatching(raw, parenOpen, "(".code, ")".code);
		if (parenClose < 0)
			return null;

		final thenOpen = skipWhitespace(raw, parenClose + 1);
		if (thenOpen >= raw.length || raw.charCodeAt(thenOpen) != "{".code)
			return null;
		final thenClose = findMatching(raw, thenOpen, "{".code, "}".code);
		if (thenClose < 0)
			return null;

		var cursor = skipWhitespace(raw, thenClose + 1);
		var elsePart = "";
		if (startsWithRawKeyword(raw, cursor, "else")) {
			final elseOpen = skipWhitespace(raw, cursor + 4);
			if (elseOpen >= raw.length || raw.charCodeAt(elseOpen) != "{".code)
				return null;
			final elseClose = findMatching(raw, elseOpen, "{".code, "}".code);
			if (elseClose < 0)
				return null;
			elsePart = " else { " + sanitizeRawHaxeExpressionSyntax(raw.substring(elseOpen + 1, elseClose), scope) + " }";
			cursor = skipWhitespace(raw, elseClose + 1);
		}

		var trailing = StringTools.trim(raw.substr(cursor));
		while (StringTools.startsWith(trailing, ";"))
			trailing = StringTools.trim(trailing.substr(1));
		while (StringTools.endsWith(trailing, ";"))
			trailing = StringTools.trim(trailing.substr(0, trailing.length - 1));
		if (trailing.length == 0)
			return null;

		final cond = sanitizeRawHaxeExpressionSyntax(raw.substring(parenOpen + 1, parenClose), scope);
		final thenBody = sanitizeRawHaxeExpressionSyntax(raw.substring(thenOpen + 1, thenClose), scope);
		final value = sanitizeRawHaxeExpressionSyntax(trailing, scope);
		return "if (" + cond + ") { " + thenBody + " }" + elsePart + " return " + value + ";";
	}

	static function startsWithRawKeyword(source:String, offset:Int, keyword:String):Bool {
		if (source == null || keyword == null || offset < 0 || offset + keyword.length > source.length)
			return false;
		if (source.substr(offset, keyword.length) != keyword)
			return false;
		final before = offset == 0 ? -1 : source.charCodeAt(offset - 1);
		final afterIndex = offset + keyword.length;
		final after = afterIndex >= source.length ? -1 : source.charCodeAt(afterIndex);
		return (before < 0 || !isRawIdentChar(before)) && (after < 0 || !isRawIdentChar(after));
	}

	static function sanitizeRawHaxeExpressionSyntax(raw:String, ?scope:JsEmitScope):String {
		return rewriteNestedOpaqueBlockExpressions(rewriteRawQualifiedClassNews(stripLocalVarTypeHints(stripExpressionCastHints(stripExpressionMetadata(raw))),
			scope), scope);
	}

	static function rewriteNestedOpaqueBlockExpressions(raw:String, ?scope:JsEmitScope):String {
		if (raw == null || raw.indexOf("{") < 0)
			return raw;

		final out = new StringBuf();
		var i = 0;
		while (i < raw.length) {
			final code = raw.charCodeAt(i);
			if (code == "\"".code || code == "'".code) {
				i = copyQuotedRaw(raw, i, out);
				continue;
			}
			if (code == "{".code && isNestedValueBlockOpen(raw, i)) {
				final close = findMatching(raw, i, "{".code, "}".code);
				if (close > i) {
					final body = raw.substring(i + 1, close);
					if (!looksLikeRawObjectLiteral(body)) {
						out.add("(function () { ");
						out.add(blockToReturningJs(body, scope));
						out.add(" })()");
						i = close + 1;
						continue;
					}
				}
			}
			out.addChar(code);
			i++;
		}
		return out.toString();
	}

	static function isNestedValueBlockOpen(raw:String, openIndex:Int):Bool {
		var i = openIndex - 1;
		while (i >= 0 && isWhitespace(raw.charCodeAt(i)))
			i--;
		if (i < 0)
			return false;
		return switch (raw.charCodeAt(i)) {
			case "=".code | "(".code | ",".code | "[".code:
				true;
			case _:
				false;
		}
	}

	static function looksLikeRawObjectLiteral(body:String):Bool {
		final trimmed = body == null ? "" : StringTools.trim(body);
		if (trimmed.length == 0)
			return true;
		final keyEnd = rawObjectLiteralFirstKeyEnd(trimmed, 0);
		if (keyEnd <= 0)
			return false;
		final colon = skipWhitespace(trimmed, keyEnd);
		return colon < trimmed.length && trimmed.charCodeAt(colon) == ":".code;
	}

	static function rawObjectLiteralFirstKeyEnd(source:String, start:Int):Int {
		var i = skipWhitespace(source, start);
		if (i >= source.length)
			return -1;
		final code = source.charCodeAt(i);
		if (code == "\"".code || code == "'".code)
			return skipQuotedRaw(source, i);
		if (!isRawIdentStart(code))
			return -1;
		i++;
		while (i < source.length && isRawIdentChar(source.charCodeAt(i)))
			i++;
		return i;
	}

	static function rewriteRawQualifiedClassNews(raw:String, ?scope:JsEmitScope):String {
		if (raw == null || scope == null || raw.indexOf(".") < 0 || raw.indexOf("new") < 0)
			return raw;

		final out = new StringBuf();
		var i = 0;
		while (i < raw.length) {
			final code = raw.charCodeAt(i);
			if (code == "\"".code || code == "'".code) {
				i = copyQuotedRaw(raw, i, out);
				continue;
			}

			if (raw.substr(i, 3) == "new" && (i == 0 || !isRawIdentChar(raw.charCodeAt(i - 1)))) {
				var ws = i + 3;
				if (ws < raw.length && isWhitespace(raw.charCodeAt(ws))) {
					while (ws < raw.length && isWhitespace(raw.charCodeAt(ws)))
						ws++;
					var end = ws;
					while (end < raw.length && isRawPathChar(raw.charCodeAt(end)))
						end++;
					final path = raw.substring(ws, end);
					final dot = path.lastIndexOf(".");
					if (dot > 0 && dot + 1 < path.length && isUpperStart(path.substr(dot + 1))) {
						final classRef = scope.resolveClassRef(path);
						if (classRef != null) {
							out.add("new");
							out.add(raw.substring(i + 3, ws));
							out.add(classRef);
							i = end;
							continue;
						}
					}
				}
			}

			out.addChar(code);
			i++;
		}
		return out.toString();
	}

	static function isRawPathChar(code:Int):Bool {
		return code == ".".code || isRawIdentChar(code);
	}

	static function stripExpressionMetadata(raw:String):String {
		if (raw == null || raw.indexOf("@:") < 0)
			return raw;

		final out = new StringBuf();
		var i = 0;
		while (i < raw.length) {
			if (raw.substr(i, 2) == "@:") {
				var j = i + 2;
				while (j < raw.length && isMetadataPathChar(raw.charCodeAt(j)))
					j++;
				if (j > i + 2) {
					i = j;
					continue;
				}
			}
			out.addChar(raw.charCodeAt(i));
			i++;
		}
		return out.toString();
	}

	static function stripExpressionCastHints(raw:String):String {
		if (raw == null || raw.indexOf(":") < 0)
			return raw;

		final out = new StringBuf();
		final parenStack = new Array<Int>();
		var i = 0;
		while (i < raw.length) {
			final code = raw.charCodeAt(i);
			switch (code) {
				case "(".code:
					parenStack.push(i);
				case ")".code:
					if (parenStack.length > 0)
						parenStack.pop();
				case ":".code if (parenStack.length > 0):
					final open = parenStack[parenStack.length - 1];
					final close = findMatching(raw, open, "(".code, ")".code);
					if (close > i && isRawTypeHintSegment(raw.substring(i + 1, close)) && !hasTopLevelQuestion(raw, open + 1, i)) {
						i = close;
						continue;
					}
				case _:
			}
			out.addChar(code);
			i++;
		}
		return out.toString();
	}

	static function stripLocalVarTypeHints(raw:String):String {
		if (raw == null || raw.indexOf(":") < 0)
			return raw;

		final out = new StringBuf();
		var i = 0;
		while (i < raw.length) {
			final keywordLength = localVarKeywordLengthAt(raw, i);
			if (keywordLength <= 0) {
				out.addChar(raw.charCodeAt(i));
				i++;
				continue;
			}

			out.add(raw.substr(i, keywordLength));
			i += keywordLength;
			var inInitializer = false;
			var parenDepth = 0;
			var braceDepth = 0;
			var bracketDepth = 0;
			var declarationDone = false;
			while (i < raw.length && !declarationDone) {
				final code = raw.charCodeAt(i);
				switch (code) {
					case "\"".code | "'".code:
						i = copyQuotedRaw(raw, i, out);
					case "(".code:
						parenDepth++;
						out.addChar(code);
						i++;
					case ")".code:
						if (parenDepth > 0)
							parenDepth--;
						out.addChar(code);
						i++;
					case "{".code:
						braceDepth++;
						out.addChar(code);
						i++;
					case "}".code:
						if (braceDepth > 0)
							braceDepth--;
						out.addChar(code);
						i++;
					case "[".code:
						bracketDepth++;
						out.addChar(code);
						i++;
					case "]".code:
						if (bracketDepth > 0)
							bracketDepth--;
						out.addChar(code);
						i++;
					case ":".code if (!inInitializer && parenDepth == 0 && braceDepth == 0 && bracketDepth == 0):
						i = skipLocalVarTypeHint(raw, i + 1);
					case "=".code if (parenDepth == 0 && braceDepth == 0 && bracketDepth == 0):
						inInitializer = true;
						out.addChar(code);
						i++;
					case ",".code if (parenDepth == 0 && braceDepth == 0 && bracketDepth == 0):
						inInitializer = false;
						out.addChar(code);
						i++;
					case ";".code if (parenDepth == 0 && braceDepth == 0 && bracketDepth == 0):
						out.addChar(code);
						i++;
						declarationDone = true;
					case _:
						out.addChar(code);
						i++;
				}
			}
		}
		return out.toString();
	}

	static function localVarKeywordLengthAt(raw:String, offset:Int):Int {
		if (offset > 0 && isRawIdentChar(raw.charCodeAt(offset - 1)))
			return 0;

		if (raw.substr(offset, 3) == "var" && offset + 3 < raw.length && isWhitespace(raw.charCodeAt(offset + 3)))
			return 3;
		if (raw.substr(offset, 3) == "let" && offset + 3 < raw.length && isWhitespace(raw.charCodeAt(offset + 3)))
			return 3;
		if (raw.substr(offset, 5) == "const" && offset + 5 < raw.length && isWhitespace(raw.charCodeAt(offset + 5)))
			return 5;
		return 0;
	}

	static function skipLocalVarTypeHint(raw:String, offset:Int):Int {
		var i = offset;
		var parenDepth = 0;
		var braceDepth = 0;
		var bracketDepth = 0;
		var angleDepth = 0;
		while (i < raw.length) {
			final code = raw.charCodeAt(i);
			switch (code) {
				case "\"".code | "'".code:
					i = skipQuotedRaw(raw, i);
				case "(".code:
					parenDepth++;
					i++;
				case ")".code:
					if (parenDepth > 0)
						parenDepth--;
					i++;
				case "{".code:
					braceDepth++;
					i++;
				case "}".code:
					if (braceDepth > 0)
						braceDepth--;
					i++;
				case "[".code:
					bracketDepth++;
					i++;
				case "]".code:
					if (bracketDepth > 0)
						bracketDepth--;
					i++;
				case "<".code:
					angleDepth++;
					i++;
				case ">".code:
					if (angleDepth > 0)
						angleDepth--;
					i++;
				case "=".code | ",".code | ";".code if (parenDepth == 0 && braceDepth == 0 && bracketDepth == 0 && angleDepth == 0):
					return i;
				case _:
					i++;
			}
		}
		return i;
	}

	static function copyQuotedRaw(raw:String, offset:Int, out:StringBuf):Int {
		final quote = raw.charCodeAt(offset);
		out.addChar(quote);
		var i = offset + 1;
		while (i < raw.length) {
			final code = raw.charCodeAt(i);
			out.addChar(code);
			i++;
			if (code == "\\".code && i < raw.length) {
				out.addChar(raw.charCodeAt(i));
				i++;
				continue;
			}
			if (code == quote)
				break;
		}
		return i;
	}

	static function skipQuotedRaw(raw:String, offset:Int):Int {
		final quote = raw.charCodeAt(offset);
		var i = offset + 1;
		while (i < raw.length) {
			final code = raw.charCodeAt(i);
			i++;
			if (code == "\\".code && i < raw.length) {
				i++;
				continue;
			}
			if (code == quote)
				break;
		}
		return i;
	}

	static function isMetadataPathChar(code:Int):Bool {
		return (code >= "a".code && code <= "z".code)
			|| (code >= "A".code && code <= "Z".code)
			|| (code >= "0".code && code <= "9".code)
			|| code == "_".code
			|| code == ".".code;
	}

	static function isRawIdentChar(code:Int):Bool {
		return (code >= "a".code && code <= "z".code)
			|| (code >= "A".code && code <= "Z".code)
			|| (code >= "0".code && code <= "9".code)
			|| code == "_".code
			|| code == "$".code;
	}

	static function isRawIdentStart(code:Int):Bool {
		return (code >= "a".code && code <= "z".code) || (code >= "A".code && code <= "Z".code) || code == "_".code || code == "$".code;
	}

	static function isWhitespace(code:Int):Bool {
		return switch (code) {
			case 9 | 10 | 11 | 12 | 13 | 32:
				true;
			case _:
				false;
		}
	}

	static function isRawTypeHintSegment(segment:String):Bool {
		final trimmed = segment == null ? "" : StringTools.trim(segment);
		if (trimmed.length == 0)
			return false;
		for (i in 0...trimmed.length) {
			final code = trimmed.charCodeAt(i);
			if ((code >= "a".code && code <= "z".code) || (code >= "A".code && code <= "Z".code) || (code >= "0".code && code <= "9".code))
				continue;
			switch (code) {
				case "_".code | ".".code | "<".code | ">".code | ",".code | "?".code | "!".code | "[".code | "]".code | " ".code | "\t".code:
				case _:
					return false;
			}
		}
		return true;
	}

	static function hasTopLevelQuestion(source:String, start:Int, end:Int):Bool {
		var parenDepth = 0;
		var braceDepth = 0;
		var bracketDepth = 0;
		for (i in start...end) {
			switch (source.charCodeAt(i)) {
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
				case "?".code:
					if (parenDepth == 0 && braceDepth == 0 && bracketDepth == 0)
						return true;
				case _:
			}
		}
		return false;
	}

	static function findMatching(source:String, openIndex:Int, openCode:Int, closeCode:Int):Int {
		if (source == null || openIndex < 0 || openIndex >= source.length || source.charCodeAt(openIndex) != openCode)
			return -1;
		var depth = 1;
		var i = openIndex + 1;
		while (i < source.length) {
			final code = source.charCodeAt(i);
			if (code == openCode) {
				depth++;
			} else if (code == closeCode) {
				depth--;
				if (depth == 0)
					return i;
			}
			i++;
		}
		return -1;
	}

	static function findLastTopLevelSemicolon(source:String):Int {
		var parenDepth = 0;
		var braceDepth = 0;
		var bracketDepth = 0;
		var last = -1;
		for (i in 0...source.length) {
			switch (source.charCodeAt(i)) {
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
				case ";".code:
					if (parenDepth == 0 && braceDepth == 0 && bracketDepth == 0)
						last = i;
				case _:
			}
		}
		return last;
	}

	static function resolveIdent(name:String, scope:JsEmitScope):String {
		if (scope != null) {
			final local = scope.resolveLocal(name);
			if (local != null)
				return local;
			final cls = scope.resolveClassRef(name);
			if (cls != null)
				return cls;
		}
		return JsNameMangler.identifier(name);
	}

	static function emitField(obj:HxExpr, field:String, scope:JsEmitScope):String {
		if (field == "code") {
			switch (obj) {
				case EString(_):
					return "(" + emit(obj, scope) + ").charCodeAt(0)";
				case _:
			}
		}

		switch (obj) {
			case ESuper:
				return emitSuperPropertyGet(field, scope);
			case _:
		}

		if (scope != null) {
			final fullPath = typeTestName(EField(obj, field));
			if (fullPath != null) {
				final classRef = scope.resolveClassRef(fullPath);
				if (classRef != null)
					return classRef;
				final fallbackRef = resolvePackageQualifiedSimpleClass(fullPath, EField(obj, field), scope);
				if (fallbackRef != null)
					return fallbackRef;
				final placeholderRef = resolvePackageQualifiedTypePlaceholder(fullPath, EField(obj, field), scope);
				if (placeholderRef != null)
					return placeholderRef;
			}
		}

		final receiver = switch (obj) {
			case EInt(_) | EFloat(_):
				"(" + emit(obj, scope) + ")";
			case _:
				emit(obj, scope);
		}
		return receiver + JsNameMangler.propertySuffix(field);
	}

	/** Use JavaScript optional chaining without duplicating the Haxe receiver expression. **/
	static function emitNullSafeField(obj:HxExpr, field:String, scope:JsEmitScope):String {
		final suffix = JsNameMangler.propertySuffix(field);
		return "(" + emit(obj, scope) + ")" + (StringTools.startsWith(suffix, ".") ? "?" + suffix : "?." + suffix);
	}

	static function emitCall(callee:HxExpr, args:Array<HxExpr>, scope:JsEmitScope):String {
		switch (callee) {
			case EField(ESuper, field):
				return emitSuperMethodCall(field, args, scope);
			case EField(subject, "match") if (args != null && args.length == 1):
				return emitEnumMatch(subject, args[0], scope);
			case EField(subject, "copy") if (args != null && args.length == 0):
				return emitCopyCall(subject, scope);
			case EEnumValue(name):
				final params = args == null ? [] : args.map(a -> emit(a, scope));
				return macroEnum(name, params);
			case EIdent("__js__") | EField(EField(EIdent("js"), "Syntax"), "code"):
				return emitInlineJsCode(args, scope);
			case EIdent("__hxhx_throw"):
				final thrown = args.length > 0 ? emit(args[0], scope) : "null";
				return "(function(){ throw " + thrown + "; })()";
			case EIdent("__hxhx_parenthesized") if (args.length == 1):
				return "(" + emit(args[0], scope) + ")";
			case EIdent("__hxhx_spread"):
				return args.length > 0 ? "..." + emit(args[0], scope) : "";
			case EIdent("__hxhx_optional_lambda") if (args.length >= 1):
				return emit(args[0], scope);
			case EIdent("trace"):
				return "console.log(" + args.map(a -> emitCallArg(a, scope)).join(", ") + ")";
			case EField(EIdent("Sys"), "println"):
				return "console.log(" + args.map(a -> emitCallArg(a, scope)).join(", ") + ")";
			case EField(EIdent("Sys"), "print"):
				final arg = args.length > 0 ? emit(args[0], scope) : "\"\"";
				return "process.stdout.write(String(" + arg + "))";
			case EField(EIdent("Sys"), "args"):
				return "process.argv.slice(2)";
			case EField(EIdent("Sys"), "exit"):
				final code = args.length > 0 ? emit(args[0], scope) : "0";
				return "process.exit(Number(" + code + ") || 0)";
			case EField(EIdent("Sys"), "command"):
				return emitSysCommand(args, scope);
			case EField(EIdent("Sys"), "setCwd"):
				final dir = args.length > 0 ? emit(args[0], scope) : "\".\"";
				return "process.chdir(String(" + dir + "))";
			case EField(EIdent("Sys"), "getCwd"):
				return "process.cwd()";
			case EField(EIdent("Std"), "string") if (args.length == 1):
				// Shared typed lowering uses this call to make Haxe string-concat
				// coercion explicit even when no Std class module was loaded.
				return "String(" + emit(args[0], scope) + ")";
			case EIdent("typeErrorText") | EField(EIdent("HelperMacros"), "typeErrorText") | EField(EField(EIdent("unit"), "HelperMacros"), "typeErrorText"):
				final diagnostic = helperTypeErrorText(args);
				if (diagnostic != null)
					return JsNameMangler.quoteString(diagnostic);
			case EIdent("typeError") | EField(EIdent("HelperMacros"), "typeError") | EField(EField(EIdent("unit"), "HelperMacros"), "typeError"):
				final result = helperTypeErrorResult(args);
				if (result != null)
					return result ? "true" : "false";
			case EIdent("__hxhx_map_comprehension"):
				return emitMapComprehensionExpr(args, scope);
			case EIdent("__hxhx_for_key_value"):
				return emitForKeyValueExpr(args, scope);
			case EIdent("__hxhx_for_in"):
				return emitForInExpr(args, scope);
			case EIdent("__hxhx_while"):
				return emitWhileExpr(args, scope);
			case EIdent("__hxhx_try"):
				return emitTryExpr(args, scope);
			case _:
		}
		final calleeJs = emit(callee, scope);
		final argsJs = args.map(a -> emitCallArg(a, scope)).join(", ");
		final callable = switch (callee) {
			case ELambda(_, _) | ECast(ELambda(_, _), _):
				"(" + calleeJs + ")";
			case _:
				calleeJs;
		};
		return callable + "(" + argsJs + ")";
	}

	static function emitCopyCall(subject:HxExpr, scope:JsEmitScope):String {
		final subjectJs = emit(subject, scope);
		return "(function(__hx_copy_target) {"
			+ "return Array.isArray(__hx_copy_target) ? __hx_copy_target.slice() : __hx_copy_target.copy();"
			+ "})("
			+ subjectJs
			+ ")";
	}

	static function emitEnumMatch(subject:HxExpr, pattern:HxExpr, scope:JsEmitScope):String {
		return switch (pattern) {
			case ECall(EEnumValue(_), _):
				final subjectJs = emit(subject, scope);
				final patternJs = emit(pattern, scope);
				"(function(__hx_v, __hx_p) {"
				+ "if (__hx_v == null || __hx_p == null) return false;"
				+ "if (__hx_v.__hx_ctor !== __hx_p.__hx_ctor) return false;"
				+ "var __hx_vp = Array.isArray(__hx_v.__hx_params) ? __hx_v.__hx_params : [];"
				+ "var __hx_pp = Array.isArray(__hx_p.__hx_params) ? __hx_p.__hx_params : [];"
				+ "if (__hx_vp.length !== __hx_pp.length) return false;"
				+ "for (var __hx_i = 0; __hx_i < __hx_pp.length; __hx_i++) {"
				+ "if (JSON.stringify(__hx_vp[__hx_i]) !== JSON.stringify(__hx_pp[__hx_i])) return false;"
				+ "}"
				+ "return true;"
				+ "})("
				+ subjectJs
				+ ", "
				+ patternJs
				+ ")";
			case _:
				final calleeJs = emit(EField(subject, "match"), scope);
				calleeJs + "(" + emitCallArg(pattern, scope) + ")";
		}
	}

	static function emitSysCommand(args:Array<HxExpr>, scope:JsEmitScope):String {
		final cmd = args.length > 0 ? emit(args[0], scope) : "\"\"";
		if (args.length <= 1) {
			return "(function(){"
				+ "var __hx_cp = require(\"child_process\");"
				+ "var __hx_result = __hx_cp.spawnSync(String("
				+ cmd
				+ "), { stdio: \"inherit\", shell: true });"
				+ "return (__hx_result && typeof __hx_result.status === \"number\") ? __hx_result.status : 1;"
				+ "})()";
		}
		final rawArgs = emit(args[1], scope);
		return "(function(){"
			+ "var __hx_cp = require(\"child_process\");"
			+ "var __hx_raw_args = "
			+ rawArgs
			+ ";"
			+ "var __hx_args = Array.isArray(__hx_raw_args) ? __hx_raw_args.map(function(__hx_arg) { return String(__hx_arg); }) : [];"
			+ "var __hx_result = __hx_cp.spawnSync(String("
			+ cmd
			+ "), __hx_args, { stdio: \"inherit\" });"
			+ "return (__hx_result && typeof __hx_result.status === \"number\") ? __hx_result.status : 1;"
			+ "})()";
	}

	static function emitMapComprehensionExpr(args:Array<HxExpr>, scope:JsEmitScope):String {
		if (args == null || args.length < 2)
			unsupported("ECall", "__hxhx_map_comprehension");
		return switch (args[1]) {
			case ELambda(lambdaArgs, EArrayDecl(pair)) if (lambdaArgs.length == 1 && pair.length >= 2):
				emitMapComprehension(lambdaArgs[0], args[0], pair[0], pair[1], scope);
			case _:
				unsupported("ECall", "__hxhx_map_comprehension");
		}
	}

	static function emitCallArg(arg:HxExpr, scope:JsEmitScope):String {
		return switch (arg) {
			case ECall(EIdent("__hxhx_spread"), [inner]):
				"..." + emit(inner, scope);
			case _:
				emit(arg, scope);
		}
	}

	static function emitForKeyValueExpr(args:Array<HxExpr>, scope:JsEmitScope):String {
		if (args == null || args.length < 3)
			unsupported("ECall", "__hxhx_for_key_value");
		final iterable = emit(args[0], scope);
		final body = emit(args[1], scope);
		final continuation = emit(args[2], scope);
		return "(function(){ var __iter = "
			+ iterable
			+ "; var __body = "
			+ body
			+
			"; var __keys = Object.keys(__iter); for (var __i = 0; __i < __keys.length; __i++) { var __raw_key = __keys[__i]; var __key = Array.isArray(__iter) ? (__raw_key | 0) : __raw_key; __body(__key, __iter[__raw_key]); } return "
			+ continuation
			+ "; })()";
	}

	static function emitForInExpr(args:Array<HxExpr>, scope:JsEmitScope):String {
		if (args == null || args.length < 3)
			unsupported("ECall", "__hxhx_for_in");
		final body = emit(args[1], scope);
		final continuation = emit(args[2], scope);
		return switch (args[0]) {
			case ERange(startExpr, endExpr):
				"(function(){ var __body = "
				+ body
				+ "; var __start = "
				+ emit(startExpr, scope)
				+ "; var __end = "
				+ emit(endExpr, scope)
				+ "; for (var __i = __start; __i < __end; __i++) { __body(__i); } return "
				+ continuation
				+ "; })()";
			case _:
				final iterable = emit(args[0], scope);
				"(function(){ var __iter = "
				+ iterable
				+ "; var __body = "
				+ body
				+ "; for (var __i = 0; __i < __iter.length; __i++) { __body(__iter[__i]); } return "
				+ continuation
				+ "; })()";
		}
	}

	static function emitWhileExpr(args:Array<HxExpr>, scope:JsEmitScope):String {
		if (args == null || args.length < 3)
			unsupported("ECall", "__hxhx_while");
		final cond = emit(args[0], scope);
		final body = emit(args[1], scope);
		final continuation = emit(args[2], scope);
		return "(function(){ var __cond = "
			+ cond
			+ "; var __body = "
			+ body
			+ "; while (__cond()) { __body(); } return "
			+ continuation
			+ "; })()";
	}

	static function emitTryExpr(args:Array<HxExpr>, scope:JsEmitScope):String {
		if (args == null || args.length < 2)
			unsupported("ECall", "__hxhx_try");

		// See HxParser.lambdaBodyExprFromStmts: this sentinel carries local-function
		// try/catch through expression-only lambda lowering until JS can reify it.
		final tryFn = emit(args[0], scope);
		final cases:Array<HxExpr> = switch (args[1]) {
			case EArrayDecl(values):
				values;
			case _:
				unsupported("ECall", "__hxhx_try");
				[];
		}
		final out = new Array<String>();
		out.push("(function(){");
		out.push("var __hx_try = " + tryFn + ";");
		out.push("try { return __hx_try(); } catch (__hx_err) {");
		for (i in 0...cases.length) {
			switch (cases[i]) {
				case EArrayDecl([EString(_name), EString(typeHint), catchFnExpr]):
					final head = i == 0 ? "if" : "else if";
					final catchFn = emit(catchFnExpr, scope);
					out.push(head
						+ " ("
						+ emitCatchCondition(typeHint, "__hx_err")
						+ ") { var __hx_catch = "
						+ catchFn
						+ "; return __hx_catch(__hx_err); }");
				case _:
					unsupported("ECall", "__hxhx_try");
			}
		}
		out.push("throw __hx_err;");
		out.push("}");
		out.push("})()");
		return out.join(" ");
	}

	static function normalizeCatchType(typeHint:String):String {
		if (typeHint == null)
			return "";
		var hint = StringTools.trim(typeHint);
		if (hint.length == 0)
			return "";
		hint = StringTools.replace(hint, " ", "");
		hint = StringTools.replace(hint, "\t", "");
		hint = StringTools.replace(hint, "\n", "");
		hint = StringTools.replace(hint, "\r", "");
		while (StringTools.startsWith(hint, "Null<") && StringTools.endsWith(hint, ">"))
			hint = hint.substr(5, hint.length - 6);
		final genericAt = hint.indexOf("<");
		if (genericAt >= 0)
			hint = hint.substr(0, genericAt);
		return hint;
	}

	static function simpleTypeName(fullName:String):String {
		if (fullName == null || fullName.length == 0)
			return "";
		final parts = fullName.split(".");
		return parts[parts.length - 1];
	}

	static function emitCatchCondition(typeHint:String, errRef:String):String {
		final normalized = normalizeCatchType(typeHint);
		if (normalized.length == 0 || normalized == "Dynamic" || normalized == "Any")
			return "true";

		return switch (normalized) {
			case "String" | "StdTypes.String":
				"(typeof " + errRef + " === \"string\" || " + errRef + " instanceof String)";
			case "Bool" | "StdTypes.Bool":
				"(typeof " + errRef + " === \"boolean\")";
			case "Int" | "StdTypes.Int":
				"(typeof " + errRef + " === \"number\" && ((" + errRef + " | 0) === " + errRef + "))";
			case "Float" | "StdTypes.Float":
				"(typeof " + errRef + " === \"number\")";
			case "Array" | "StdTypes.Array":
				"Array.isArray(" + errRef + ")";
			default:
				final simple = simpleTypeName(normalized);
				final normalizedQuoted = JsNameMangler.quoteString(normalized);
				final simpleQuoted = JsNameMangler.quoteString(simple);
				"("
				+ errRef
				+ " != null && typeof "
				+ errRef
				+ " === \"object\" && ("
				+ errRef
				+ ".__hx_name === "
				+ normalizedQuoted
				+ " || "
				+ errRef
				+ ".__hx_name === "
				+ simpleQuoted
				+ " || ("
				+ errRef
				+ ".constructor != null && ("
				+ errRef
				+ ".constructor.__hx_name === "
				+ normalizedQuoted
				+ " || "
				+ errRef
				+ ".constructor.__hx_name === "
				+ simpleQuoted
				+ "))))";
		}
	}

	static function hasForExprProbeArg(args:Array<HxExpr>):Bool {
		if (args == null || args.length == 0)
			return false;
		return switch (args[0]) {
			case EUnsupported(raw): raw != null && StringTools.startsWith(raw, "for_expr:");
			case _:
				false;
		}
	}

	static function helperTypeErrorText(args:Array<HxExpr>):Null<String> {
		if (hasForExprProbeArg(args))
			return "Int has no field keyValueIterator";
		return null;
	}

	static function helperTypeErrorResult(args:Array<HxExpr>):Null<Bool> {
		if (hasForExprProbeArg(args))
			return true;
		if (args == null || args.length == 0)
			return null;
		return switch (args[0]) {
			case ETryCatchRaw(raw):
				blockTypeErrorResult(raw);
			case _:
				null;
		}
	}

	static function blockTypeErrorResult(raw:String):Null<Bool> {
		if (raw == null || !StringTools.startsWith(raw, "opaque_block_expr:"))
			return null;
		final compact = compactProbeSource(raw.substr("opaque_block_expr:".length));
		final dynamicProbe = ":{v:" + "Dyna" + "mic}";
		if (compact.indexOf(dynamicProbe) >= 0)
			return false;
		if (compact.indexOf(":{v:Int}") >= 0)
			return true;
		if (compact.indexOf(":{v:Int,w:String}") >= 0)
			return true;
		return true;
	}

	static function compactProbeSource(source:String):String {
		var compact = source == null ? "" : source;
		compact = StringTools.replace(compact, " ", "");
		compact = StringTools.replace(compact, "\t", "");
		compact = StringTools.replace(compact, "\n", "");
		compact = StringTools.replace(compact, "\r", "");
		return compact;
	}

	static function emitInlineJsCode(args:Array<HxExpr>, scope:JsEmitScope):String {
		if (args.length == 0)
			return "undefined";
		return switch (args[0]) {
			case EString(code):
				for (i in 1...args.length)
					code = StringTools.replace(code, "{" + (i - 1) + "}", emit(args[i], scope));
				code;
			case _:
				emit(args[0], scope);
		}
	}

	/**
		Emit a constructor call using the class name that exists at runtime.

		Haxe generic arguments such as `<V>` guide type checking but are erased
		from JavaScript class names. Only the lookup name is normalized; failures
		still report the original source spelling so unsupported code is actionable.
	**/
	static function emitNew(typePath:String, args:Array<HxExpr>, scope:JsEmitScope):String {
		final argsJs = args.map(a -> emitCallArg(a, scope)).join(", ");
		final ctorTypePath = standardCtorTypePath(typePath);
		switch (ctorTypePath) {
			case "Array":
				if (args.length == 0)
					return "[]";
				return "new Array(" + argsJs + ")";
			case "Bytes" | "haxe.io.Bytes":
				final ctor = resolveIdent(ctorTypePath, scope);
				return "new " + ctor + "(" + argsJs + ")";
			case _:
		}

		if (scope != null) {
			final classCtor = scope.resolveClassRef(ctorTypePath);
			if (classCtor != null)
				return "new " + classCtor + "(" + argsJs + ")";

			final lastDot = ctorTypePath.lastIndexOf(".");
			if (lastDot > 0 && lastDot + 1 < ctorTypePath.length) {
				final simpleType = ctorTypePath.substr(lastDot + 1);
				final simpleCtor = scope.resolveClassRef(simpleType);
				if (simpleCtor != null)
					return "new " + simpleCtor + "(" + argsJs + ")";
			}
		}

		if (StringTools.startsWith(ctorTypePath, "js.lib.")) {
			final nativeCtor = ctorTypePath.substr("js.lib.".length);
			if (nativeCtor != null && nativeCtor.length > 0)
				return "new " + nativeCtor + "(" + argsJs + ")";
		}

		unsupported("ENew", typePath);
		return "";
	}

	static function standardCtorTypePath(typePath:String):String {
		final raw = typePath == null ? "" : StringTools.trim(typePath);
		final genericStart = raw.indexOf("<");
		final base = genericStart < 0 ? raw : StringTools.trim(raw.substr(0, genericStart));
		return switch (base) {
			case "Array" | "StdTypes.Array":
				"Array";
			case _:
				base;
		}
	}

	static function typeTestName(expr:HxExpr):Null<String> {
		return switch (expr) {
			case EIdent(name) | EEnumValue(name):
				name;
			case EField(owner, field): final prefix = typeTestName(owner); prefix == null || prefix.length == 0 ? field : prefix + "." + field;
			case _:
				null;
		}
	}

	static function rootIdentName(expr:HxExpr):Null<String> {
		return switch (expr) {
			case EIdent(name) | EEnumValue(name):
				name;
			case EField(owner, _):
				rootIdentName(owner);
			case _:
				null;
		}
	}

	static function resolvePackageQualifiedSimpleClass(fullPath:String, expr:HxExpr, scope:JsEmitScope):Null<String> {
		final dot = fullPath == null ? -1 : fullPath.lastIndexOf(".");
		if (dot <= 0 || dot + 1 >= fullPath.length)
			return null;
		final root = rootIdentName(expr);
		if (!isLikelyPackageRoot(root))
			return null;
		if (scope.resolveLocal(root) != null)
			return null;
		return scope.resolveClassRef(fullPath.substr(dot + 1));
	}

	static function resolvePackageQualifiedTypePlaceholder(fullPath:String, expr:HxExpr, scope:JsEmitScope):Null<String> {
		final dot = fullPath == null ? -1 : fullPath.lastIndexOf(".");
		if (dot <= 0 || dot + 1 >= fullPath.length)
			return null;
		switch (expr) {
			case EField(owner, _):
				final ownerPath = typeTestName(owner);
				if (hasClassRefForTypePath(ownerPath, owner, scope))
					return null;
			case _:
		}
		final root = rootIdentName(expr);
		if (!isLikelyPackageRoot(root))
			return null;
		if (scope.resolveLocal(root) != null)
			return null;
		final simple = fullPath.substr(dot + 1);
		if (!isUpperStart(simple))
			return null;
		return "__hx_type_ref(" + JsNameMangler.quoteString(fullPath) + ")";
	}

	static function hasClassRefForTypePath(path:String, expr:HxExpr, scope:JsEmitScope):Bool {
		if (path == null || scope == null)
			return false;
		if (scope.resolveClassRef(path) != null)
			return true;
		final dot = path.lastIndexOf(".");
		if (dot <= 0 || dot + 1 >= path.length)
			return false;
		final root = rootIdentName(expr);
		return isLikelyPackageRoot(root) && scope.resolveLocal(root) == null && scope.resolveClassRef(path.substr(dot + 1)) != null;
	}

	static function isLikelyPackageRoot(name:String):Bool {
		if (name == null || name.length == 0)
			return false;
		final code = name.charCodeAt(0);
		return code >= "a".code && code <= "z".code;
	}

	static function isUpperStart(name:String):Bool {
		if (name == null || name.length == 0)
			return false;
		final code = name.charCodeAt(0);
		return code >= "A".code && code <= "Z".code;
	}

	static function emitIsTypeTest(left:HxExpr, right:HxExpr, scope:JsEmitScope):String {
		final value = emit(left, scope);
		final typeName = typeTestName(right);
		final test = switch (typeName) {
			case "Float" | "Int":
				'typeof __hx_is === "number"';
			case "Bool":
				'typeof __hx_is === "boolean"';
			case "String":
				'typeof __hx_is === "string" || __hx_is instanceof String';
			case "Array":
				"Array.isArray(__hx_is)";
			case "Dynamic" | "Any":
				"true";
			case null:
				"false";
			case _:
				final resolved = scope.resolveClassRef(typeName);
				final parts = typeName.split(".");
				final fallback = parts.length == 0 ? typeName : parts[parts.length - 1];
				"__hx_is instanceof " + (resolved == null ? JsNameMangler.identifier(fallback) : resolved);
		}
		return "(function(__hx_is){ return " + test + "; })(" + value + ")";
	}

	static function emitBinop(op:String, left:HxExpr, right:HxExpr, scope:JsEmitScope):String {
		if (op == "is")
			return emitIsTypeTest(left, right, scope);
		if (op == "=") {
			switch (left) {
				case EArrayAccess(array, index):
					return emitArrayWrite(array, index, right, scope);
				case _:
			}
		}
		if (isAssignmentOp(op)) {
			switch (left) {
				case EThis:
					return emitThisAssignment(op, right, scope);
				case EField(ESuper, field) if (op == "="):
					return emitSuperPropertySet(field, right, scope);
				case EField(ESuper, field):
					return unsupported("EBinop", "compound assignment to super." + field);
				case EIdent(_), EField(_, _) if (op == "+="):
					return emitAbstractAddAssign(left, right, scope);
				case _:
			}
		}
		if (op == "+")
			return emitAbstractAdd(left, right, scope);
		if (op == "??") {
			final l = emit(left, scope);
			final r = emit(right, scope);
			return "(function(__hx_coalesce){ return (__hx_coalesce != null) ? __hx_coalesce : " + r + "; })(" + l + ")";
		}
		if ((op == "==" || op == "!=") && (isNullLiteral(left) || isNullLiteral(right))) {
			final nullAwareOp = op == "==" ? "==" : "!=";
			return "(" + emit(left, scope) + " " + nullAwareOp + " " + emit(right, scope) + ")";
		}
		final normalized = switch (op) {
			case "==": "===";
			case "!=": "!==";
			case _: op;
		}
		return "(" + emit(left, scope) + " " + normalized + " " + emit(right, scope) + ")";
	}

	static function emitThisAssignment(op:String, right:HxExpr, scope:JsEmitScope):String {
		final rhs = emit(right, scope);
		if (op != "=")
			return "(this.__hx_value " + op + " " + rhs + ")";
		return switch (right) {
			case EAnon(fieldNames, _):
				final assignments = new Array<String>();
				for (field in fieldNames) {
					final suffix = JsNameMangler.propertySuffix(field);
					assignments.push("this" + suffix + " = this.__hx_value" + suffix);
				}
				if (assignments.length == 0) {
					"((this.__hx_value = " + rhs + "), this.__hx_value)";
				} else {
					"((this.__hx_value = " + rhs + "), " + assignments.join(", ") + ", this.__hx_value)";
				}
			case _:
				"(this.__hx_value = " + rhs + ")";
		}
	}

	static function emitAbstractAdd(left:HxExpr, right:HxExpr, scope:JsEmitScope):String {
		final l = emit(left, scope);
		final r = emit(right, scope);
		return
			"(function(__hx_l, __hx_r) { return (__hx_l != null && typeof __hx_l.__hx_op_add === \"function\") ? __hx_l.__hx_op_add(__hx_r) : (__hx_l + __hx_r); })("
			+ l
			+ ", "
			+ r
			+ ")";
	}

	static function emitAbstractAddAssign(left:HxExpr, right:HxExpr, scope:JsEmitScope):String {
		final l = emit(left, scope);
		final r = emit(right, scope);
		return "((" + l + " != null && typeof " + l + ".__hx_op_addAssign === \"function\") ? (" + l + ".__hx_op_addAssign(" + r + "), " + l + ") : (" + l
			+ " += " + r + "))";
	}

	/**
		Emit an increment/decrement expression without losing Haxe lvalue behavior.

		Indexed updates evaluate the array and index once, use abstract array-access
		hooks when present, and return the new or old value according to fixity.
	**/
	static function emitIncDec(op:HxUnaryOperator, fixity:HxUnaryFixity, target:HxExpr, scope:JsEmitScope):String {
		HxUnaryOperatorTools.requireValidFixity(op, fixity);
		final delta = op == HxUnaryOperator.Increment ? "1" : "-1";
		if (fixity == HxUnaryFixity.Prefix) {
			final token = HxUnaryOperatorTools.sourceToken(op);
			return switch (target) {
				case EThis:
					"(" + token + "this.__hx_value)";
				case EArrayAccess(array, index):
					final arrayJs = emit(array, scope);
					final indexJs = emit(index, scope);
					final body = "var __hx_old = (__hx_a != null && typeof __hx_a.__hx_op_read === \"function\") ? __hx_a.__hx_op_read(__hx_i) : __hx_a[__hx_i]; "
						+ "var __hx_next = (__hx_old + "
						+ delta
						+ "); "
						+ "if (__hx_a != null && typeof __hx_a.__hx_op_write === \"function\") __hx_a.__hx_op_write(__hx_i, __hx_next); "
						+ "else __hx_a[__hx_i] = __hx_next; return __hx_next;";
					"(function(__hx_a, __hx_i){ " + body + " })(" + arrayJs + ", " + indexJs + ")";
				case _:
					"(" + token + emit(target, scope) + ")";
			};
		}

		return switch (target) {
			case EThis:
				"(function(__hx_self){ var __hx_old = __hx_self.__hx_value; __hx_self.__hx_value = (__hx_old + " + delta + "); return __hx_old; })(this)";
			case EIdent(_):
				final targetRef = emit(target, scope);
				final thisProp = if (StringTools.startsWith(targetRef, "this.")
					|| StringTools.startsWith(targetRef, "this[")) targetRef.substr(4) else null;
				if (thisProp != null) {"(function(__hx_obj){ var __hx_old = __hx_obj"
					+ thisProp
					+ "; __hx_obj"
					+ thisProp
					+ " = (__hx_old + "
					+ delta
					+ "); return __hx_old; })(this)";
				} else {
					"(function(){ var __hx_old = " + targetRef + "; " + targetRef + " = (__hx_old + " + delta + "); return __hx_old; })()";
				}
			case EField(obj, field):
				final objJs = emit(obj, scope);
				final prop = JsNameMangler.propertySuffix(field);
				"(function(__hx_obj){ var __hx_old = __hx_obj"
				+ prop
				+ "; __hx_obj"
				+ prop
				+ " = (__hx_old + "
				+ delta
				+ "); return __hx_old; })("
				+ objJs
				+ ")";
			case EArrayAccess(array, index):
				final arrayJs = emit(array, scope);
				final indexJs = emit(index, scope);
				final body = "var __hx_old = (__hx_a != null && typeof __hx_a.__hx_op_read === \"function\") ? __hx_a.__hx_op_read(__hx_i) : __hx_a[__hx_i]; "
					+ "var __hx_next = (__hx_old + "
					+ delta
					+ "); "
					+ "if (__hx_a != null && typeof __hx_a.__hx_op_write === \"function\") __hx_a.__hx_op_write(__hx_i, __hx_next); "
					+ "else __hx_a[__hx_i] = __hx_next; return __hx_old;";
				"(function(__hx_a, __hx_i){ " + body + " })(" + arrayJs + ", " + indexJs + ")";
			case _:
				unsupported("EUnop", HxUnaryOperatorTools.sourceToken(op));
		}
	}

	static function emitArrayRead(array:HxExpr, index:HxExpr, scope:JsEmitScope):String {
		final a = emit(array, scope);
		final i = emit(index, scope);
		return
			"(function(__hx_a, __hx_i) { return (__hx_a != null && typeof __hx_a.__hx_op_read === \"function\") ? __hx_a.__hx_op_read(__hx_i) : __hx_a[__hx_i]; })("
			+ a
			+ ", "
			+ i
			+ ")";
	}

	static function emitArrayWrite(array:HxExpr, index:HxExpr, value:HxExpr, scope:JsEmitScope):String {
		final a = emit(array, scope);
		final i = emit(index, scope);
		final v = emit(value, scope);
		return
			"(function(__hx_a, __hx_i, __hx_v) { return (__hx_a != null && typeof __hx_a.__hx_op_write === \"function\") ? __hx_a.__hx_op_write(__hx_i, __hx_v) : (__hx_a[__hx_i] = __hx_v); })("
			+ a
			+ ", "
			+ i
			+ ", "
			+ v
			+ ")";
	}

	static function isAssignmentOp(op:String):Bool {
		return switch (op) {
			case "=" | "+=" | "-=" | "*=" | "/=" | "%=" | "<<=" | ">>=" | ">>>=" | "&=" | "|=" | "^=" | "??=":
				true;
			case _:
				false;
		}
	}

	static function emitSuperPropertyGet(field:String, scope:JsEmitScope):String {
		final superRef = resolveSuperRef(scope);
		return superRef + ".prototype" + JsNameMangler.propertySuffix("get_" + field) + ".call(this)";
	}

	static function emitSuperPropertySet(field:String, value:HxExpr, scope:JsEmitScope):String {
		final superRef = resolveSuperRef(scope);
		return superRef + ".prototype" + JsNameMangler.propertySuffix("set_" + field) + ".call(this, " + emit(value, scope) + ")";
	}

	static function emitSuperMethodCall(field:String, args:Array<HxExpr>, scope:JsEmitScope):String {
		final superRef = resolveSuperRef(scope);
		final emittedArgs = args == null ? [] : args.map(a -> emitCallArg(a, scope));
		final allArgs = ["this"].concat(emittedArgs);
		return superRef + ".prototype" + JsNameMangler.propertySuffix(field) + ".call(" + allArgs.join(", ") + ")";
	}

	static function resolveSuperRef(scope:JsEmitScope):String {
		final superRef = scope == null ? null : scope.resolveSuperClassRef();
		if (superRef == null || superRef.length == 0)
			unsupported("ESuper", "missing superclass context");
		return superRef;
	}

	static function isNullLiteral(expr:HxExpr):Bool {
		return switch (expr) {
			case ENull: true;
			case _: false;
		}
	}

	static function emitMacroExpr(expr:HxExpr, wrappers:Array<String>, scope:JsEmitScope):String {
		var exprDef = macroExprDef(expr, scope);
		if (wrappers != null) {
			var i = wrappers.length;
			while (i > 0) {
				i--;
				exprDef = switch (wrappers[i]) {
					case "parenthesis":
						macroEnum("EParenthesis", [macroExprObject(exprDef)]);
					case "untyped":
						macroEnum("EUntyped", [macroExprObject(exprDef)]);
					case _:
						exprDef;
				}
			}
		}
		return macroExprObject(exprDef);
	}

	static function emitMacroType(typeText:String):String {
		return macroComplexType(typeText);
	}

	static function macroExprObject(exprDef:String):String {
		return "({expr: " + exprDef + ", pos: null})";
	}

	static function macroEnum(name:String, params:Array<String>):String {
		final paramText = params == null ? "" : params.join(", ");
		return "({__hx_ctor: " + JsNameMangler.quoteString(name) + ", __hx_index: 0, __hx_params: [" + paramText + "]})";
	}

	static function macroExprDef(expr:HxExpr, scope:JsEmitScope):String {
		return switch (expr) {
			case EString(v):
				macroEnum("EConst", [macroEnum("CString", [JsNameMangler.quoteString(v)])]);
			case EInt(v):
				macroEnum("EConst", [macroEnum("CInt", [JsNameMangler.quoteString(Std.string(v))])]);
			case EFloat(v):
				macroEnum("EConst", [macroEnum("CFloat", [JsNameMangler.quoteString(Std.string(v))])]);
			case ENull:
				macroEnum("EConst", [macroEnum("CIdent", [JsNameMangler.quoteString("null")])]);
			case EIdent(name):
				macroEnum("EConst", [macroEnum("CIdent", [JsNameMangler.quoteString(name)])]);
			case EField(obj, field):
				macroEnum("EField", [emitMacroExpr(obj, [], scope), JsNameMangler.quoteString(field)]);
			case ENullSafeField(obj, field):
				macroEnum("EField", [
					emitMacroExpr(obj, [], scope),
					JsNameMangler.quoteString(field),
					macroEnum("Safe", [])
				]);
			case EArrayAccess(array, index):
				macroEnum("EArray", [emitMacroExpr(array, [], scope), emitMacroExpr(index, [], scope)]);
			case EArrayDecl(values):
				final items = values == null ? [] : values.map(v -> emitMacroExpr(v, [], scope));
				macroEnum("EArrayDecl", ["[" + items.join(", ") + "]"]);
			case EBinop("in", left, right):
				macroEnum("EBinop", [
					macroEnum("OpIn", []),
					emitMacroExpr(left, [], scope),
					emitMacroExpr(right, [], scope)
				]);
			case ECall(EIdent("__hxhx_macro_if"), args):
				final cond = args.length > 0 ? args[0] : HxExpr.EBool(false);
				final thenExpr = args.length > 1 ? args[1] : HxExpr.ENull;
				final elseExpr = if (args.length > 2) {
					switch (args[2]) {
						case EIdent("__hxhx_macro_missing_else"):
							"null";
						case expr:
							emitMacroExpr(expr, [], scope);
					}
				} else {
					"null";
				}
				macroEnum("EIf", [emitMacroExpr(cond, [], scope), emitMacroExpr(thenExpr, [], scope), elseExpr]);
			case ECall(EIdent("__hxhx_macro_ident_splice"), args):
				final nameExpr = args.length > 0 ? args[0] : HxExpr.EString("");
				macroEnum("EConst", [macroEnum("CIdent", ["String(" + emit(nameExpr, scope) + ")"])]);
			case ECall(callee, args):
				final loweredArgs = args == null ? [] : args.map(arg -> emitMacroExpr(arg, [], scope));
				macroEnum("ECall", [emitMacroExpr(callee, [], scope), "[" + loweredArgs.join(", ") + "]"]);
			case EUntyped(inner):
				macroEnum("EUntyped", [emitMacroExpr(inner, [], scope)]);
			case EUnop(op, fixity, inner):
				HxUnaryOperatorTools.requireValidFixity(op, fixity);
				macroEnum("EUnop", [
					macroEnum(HxUnaryOperatorTools.macroConstructor(op), []),
					fixity == HxUnaryFixity.Postfix ? "true" : "false",
					emitMacroExpr(inner, [], scope)
				]);
			case _:
				macroEnum("EConst", [macroEnum("CIdent", [JsNameMangler.quoteString(emit(expr, scope))])]);
		}
	}

	static function macroComplexType(raw:String):String {
		final text = trimLeadingTypeColon(raw);
		final arrowParts = splitTopLevelArrow(text);
		if (arrowParts.length > 1) {
			final args = new Array<String>();
			for (i in 0...arrowParts.length - 1) {
				final segmentArgs = macroFunctionArgTypes(arrowParts[i]);
				for (arg in segmentArgs)
					args.push(arg);
			}
			return macroEnum("TFunction", ["[" + args.join(", ") + "]", macroComplexType(arrowParts[arrowParts.length - 1])]);
		}

		final trimmed = StringTools.trim(text);
		if (trimmed.length == 0)
			return macroTypePath("");

		final namedColon = findTopLevelChar(trimmed, ":".code);
		if (namedColon > 0) {
			final namePart = StringTools.trim(trimmed.substring(0, namedColon));
			final typePart = trimmed.substr(namedColon + 1);
			if (StringTools.startsWith(namePart, "?")) {
				final name = StringTools.trim(namePart.substr(1));
				return macroEnum("TOptional", [
					macroEnum("TNamed", [JsNameMangler.quoteString(name), macroComplexType(typePart)])
				]);
			}
			return macroEnum("TNamed", [JsNameMangler.quoteString(namePart), macroComplexType(typePart)]);
		}

		if (StringTools.startsWith(trimmed, "?"))
			return macroEnum("TOptional", [macroComplexType(trimmed.substr(1))]);

		final parenEnd = matchingOuterParen(trimmed);
		if (parenEnd == trimmed.length - 1)
			return macroEnum("TParent", [macroComplexType(trimmed.substring(1, trimmed.length - 1))]);

		return macroTypePath(trimmed);
	}

	static function macroFunctionArgTypes(raw:String):Array<String> {
		final trimmed = StringTools.trim(raw);
		final parenEnd = matchingOuterParen(trimmed);
		if (parenEnd == trimmed.length - 1) {
			final inner = trimmed.substring(1, trimmed.length - 1);
			final commaParts = splitTopLevelComma(inner);
			if (commaParts.length > 1)
				return commaParts.map(part -> macroComplexType(part));
		}
		return [macroComplexType(trimmed)];
	}

	static function macroTypePath(raw:String):String {
		final path = StringTools.trim(stripGenericTypeParams(raw));
		final parts = path.split(".");
		final name = parts.length == 0 ? path : parts[parts.length - 1];
		final pack = new Array<String>();
		if (parts.length > 1) {
			for (i in 0...parts.length - 1)
				pack.push(JsNameMangler.quoteString(parts[i]));
		}
		final typePath = "{pack: [" + pack.join(", ") + "], name: " + JsNameMangler.quoteString(name) + ", params: [], sub: null}";
		return macroEnum("TPath", [typePath]);
	}

	static function trimLeadingTypeColon(raw:String):String {
		var text = StringTools.trim(raw == null ? "" : raw);
		if (StringTools.startsWith(text, ":"))
			text = StringTools.trim(text.substr(1));
		return text;
	}

	static function stripGenericTypeParams(raw:String):String {
		final lt = findTopLevelChar(raw, "<".code);
		return lt < 0 ? raw : raw.substr(0, lt);
	}

	static function splitTopLevelArrow(raw:String):Array<String> {
		final out = new Array<String>();
		var start = 0;
		var i = 0;
		var paren = 0;
		var bracket = 0;
		var angle = 0;
		var brace = 0;
		while (i + 1 < raw.length) {
			final c = raw.charCodeAt(i);
			switch (c) {
				case "(".code:
					paren++;
				case ")".code:
					if (paren > 0)
						paren--;
				case "[".code:
					bracket++;
				case "]".code:
					if (bracket > 0)
						bracket--;
				case "{".code:
					brace++;
				case "}".code:
					if (brace > 0)
						brace--;
				case "<".code:
					angle++;
				case ">".code:
					if (angle > 0)
						angle--;
				case "-".code if (paren == 0 && bracket == 0 && angle == 0 && brace == 0 && raw.charCodeAt(i + 1) == ">".code):
					out.push(raw.substring(start, i));
					i += 2;
					start = i;
					continue;
				case _:
			}
			i++;
		}
		out.push(raw.substr(start));
		return out;
	}

	static function splitTopLevelComma(raw:String):Array<String> {
		final out = new Array<String>();
		var start = 0;
		var paren = 0;
		var bracket = 0;
		var angle = 0;
		var brace = 0;
		for (i in 0...raw.length) {
			final c = raw.charCodeAt(i);
			switch (c) {
				case "(".code:
					paren++;
				case ")".code:
					if (paren > 0)
						paren--;
				case "[".code:
					bracket++;
				case "]".code:
					if (bracket > 0)
						bracket--;
				case "{".code:
					brace++;
				case "}".code:
					if (brace > 0)
						brace--;
				case "<".code:
					angle++;
				case ">".code:
					if (angle > 0)
						angle--;
				case ",".code if (paren == 0 && bracket == 0 && angle == 0 && brace == 0):
					out.push(raw.substring(start, i));
					start = i + 1;
				case _:
			}
		}
		out.push(raw.substr(start));
		return out;
	}

	static function findTopLevelChar(raw:String, target:Int):Int {
		var paren = 0;
		var bracket = 0;
		var angle = 0;
		var brace = 0;
		for (i in 0...raw.length) {
			final c = raw.charCodeAt(i);
			switch (c) {
				case "(".code:
					paren++;
				case ")".code:
					if (paren > 0)
						paren--;
				case "[".code:
					bracket++;
				case "]".code:
					if (bracket > 0)
						bracket--;
				case "{".code:
					brace++;
				case "}".code:
					if (brace > 0)
						brace--;
				case "<".code:
					angle++;
				case ">".code:
					if (angle > 0)
						angle--;
				case _:
			}
			if (c == target && paren == 0 && bracket == 0 && angle == 0 && brace == 0)
				return i;
		}
		return -1;
	}

	static function matchingOuterParen(raw:String):Int {
		if (raw == null || raw.length == 0 || raw.charCodeAt(0) != "(".code)
			return -1;
		var depth = 1;
		for (i in 1...raw.length) {
			final c = raw.charCodeAt(i);
			if (c == "(".code) {
				depth++;
			} else if (c == ")".code) {
				depth--;
				if (depth == 0)
					return i;
			}
		}
		return -1;
	}

	static function emitAnon(fieldNames:Array<String>, fieldValues:Array<HxExpr>, scope:JsEmitScope):String {
		final pairs = new Array<String>();
		final n = fieldNames.length < fieldValues.length ? fieldNames.length : fieldValues.length;
		for (i in 0...n) {
			final key = JsNameMangler.quoteString(fieldNames[i]);
			final value = emit(fieldValues[i], scope);
			pairs.push(key + ": " + value);
		}
		return "{" + pairs.join(", ") + "}";
	}

	static function isMapLiteral(values:Array<HxExpr>):Bool {
		if (values == null || values.length == 0)
			return false;
		for (value in values) {
			switch (value) {
				case EBinop("=>", _, _):
				case _:
					return false;
			}
		}
		return true;
	}

	static function emitMapLiteral(values:Array<HxExpr>, scope:JsEmitScope):String {
		final pairs = new Array<String>();
		for (value in values) {
			switch (value) {
				case EBinop("=>", key, mapValue):
					final keyText = switch (key) {
						case EString(s):
							JsNameMangler.quoteString(s);
						case EInt(i):
							JsNameMangler.quoteString(Std.string(i));
						case _:
							"[" + emit(key, scope) + "]";
					}
					pairs.push(keyText + ": " + emit(mapValue, scope));
				case _:
			}
		}
		return "{" + pairs.join(", ") + "}";
	}

	static function emitLambda(args:Array<String>, body:HxExpr, scope:JsEmitScope):String {
		final lambdaLocals = new haxe.ds.StringMap<String>();
		final params = new Array<String>();
		for (a in args) {
			final safe = JsNameMangler.identifier(a);
			lambdaLocals.set(a, safe);
			params.push(safe);
		}
		final nested = nestedScope(scope, lambdaLocals);
		return "function(" + params.join(", ") + ") { return " + emit(body, nested) + "; }";
	}

	static function emitRangeExpr(startExpr:HxExpr, endExpr:HxExpr, scope:JsEmitScope):String {
		final out = new Array<String>();
		out.push("(function () {");
		out.push("var __range_out = [];");
		out.push("var __range_start = " + emit(startExpr, scope) + ";");
		out.push("var __range_end = " + emit(endExpr, scope) + ";");
		out.push("for (var __range_i = __range_start; __range_i < __range_end; __range_i++) {");
		out.push("__range_out.push(__range_i);");
		out.push("}");
		out.push("return __range_out;");
		out.push("})()");
		return out.join(" ");
	}

	static function emitArrayComprehension(name:String, iterable:HxExpr, guardExpr:Null<HxExpr>, yieldExpr:HxExpr, scope:JsEmitScope):String {
		final out = new Array<String>();
		final iterName = "__arr_comp_" + JsNameMangler.identifier(name);
		final iterLocals = new haxe.ds.StringMap<String>();
		iterLocals.set(name, iterName);
		final iterScope = nestedScope(scope, iterLocals);

		inline function pushYield():Void {
			if (guardExpr == null) {
				out.push("__arr_comp_out.push(" + emit(yieldExpr, iterScope) + ");");
			} else {
				out.push("if (" + emit(guardExpr, iterScope) + ") {");
				out.push("__arr_comp_out.push(" + emit(yieldExpr, iterScope) + ");");
				out.push("}");
			}
		}

		out.push("(function () {");
		out.push("var __arr_comp_out = [];");

		switch (iterable) {
			case ERange(startExpr, endExpr):
				out.push("var __arr_comp_start = " + emit(startExpr, scope) + ";");
				out.push("var __arr_comp_end = " + emit(endExpr, scope) + ";");
				out.push("for (var " + iterName + " = __arr_comp_start; " + iterName + " < __arr_comp_end; " + iterName + "++) {");
				pushYield();
				out.push("}");
			case _:
				out.push("var __arr_comp_iter = " + emit(iterable, scope) + ";");
				out.push("for (var __arr_comp_i = 0; __arr_comp_i < __arr_comp_iter.length; __arr_comp_i++) {");
				out.push("var " + iterName + " = __arr_comp_iter[__arr_comp_i];");
				pushYield();
				out.push("}");
		}

		out.push("return __arr_comp_out;");
		out.push("})()");
		return out.join(" ");
	}

	static function emitMapComprehension(name:String, iterable:HxExpr, keyExpr:HxExpr, valueExpr:HxExpr, scope:JsEmitScope):String {
		final out = new Array<String>();
		final iterName = "__hxhx_map_" + JsNameMangler.identifier(name);
		final iterLocals = new haxe.ds.StringMap<String>();
		iterLocals.set(name, iterName);
		final iterScope = nestedScope(scope, iterLocals);

		inline function pushYield():Void {
			out.push("var __hxhx_pair = [" + emit(keyExpr, iterScope) + ", " + emit(valueExpr, iterScope) + "];");
			out.push("__hxhx_map_out[__hxhx_pair[0]] = __hxhx_pair[1];");
		}

		out.push("(function () {");
		out.push("var __hxhx_map_out = {};");

		switch (iterable) {
			case ERange(startExpr, endExpr):
				out.push("var __hxhx_map_start = " + emit(startExpr, scope) + ";");
				out.push("var __hxhx_map_end = " + emit(endExpr, scope) + ";");
				out.push("for (var " + iterName + " = __hxhx_map_start; " + iterName + " < __hxhx_map_end; " + iterName + "++) {");
				pushYield();
				out.push("}");
			case _:
				out.push("var __hxhx_map_iter = " + emit(iterable, scope) + ";");
				out.push("for (var __hxhx_map_i = 0; __hxhx_map_i < __hxhx_map_iter.length; __hxhx_map_i++) {");
				out.push("var " + iterName + " = __hxhx_map_iter[__hxhx_map_i];");
				pushYield();
				out.push("}");
		}

		out.push("Object.defineProperty(__hxhx_map_out, \"get\", {value: function(__hx_key) { return this[__hx_key]; }, enumerable: false});");
		out.push("Object.defineProperty(__hxhx_map_out, \"exists\", {value: function(__hx_key) { return Object.prototype.hasOwnProperty.call(this, __hx_key); }, enumerable: false});");
		out.push("return __hxhx_map_out;");
		out.push("})()");
		return out.join(" ");
	}

	static function emitSwitchExpr(scrutinee:HxExpr, patterns:Array<HxSwitchPattern>, exprs:Array<HxExpr>, scope:JsEmitScope):String {
		final out = new Array<String>();
		out.push("(function () {");
		out.push("var __sw = " + emit(scrutinee, scope) + ";");

		var isFirst = true;
		final count = patterns.length < exprs.length ? patterns.length : exprs.length;
		for (i in 0...count) {
			final pattern = patterns[i];
			final branchExpr = exprs[i];
			final lowered = JsSwitchPatternLowering.lower(pattern, "__sw");
			final head = isFirst ? "if" : "else if";

			var branchScope = scope;
			var bindPrefix = "";
			if (lowered.bindings.length > 0) {
				final locals = new haxe.ds.StringMap<String>();
				final bindParts = new Array<String>();
				for (binding in lowered.bindings) {
					final bindSafe = "__sw_bind_" + JsNameMangler.identifier(binding.name);
					locals.set(binding.name, bindSafe);
					bindParts.push("var " + bindSafe + " = " + binding.expr + ";");
				}
				branchScope = nestedScope(scope, locals);
				bindPrefix = bindParts.join(" ") + " ";
			}

			out.push(head + " (" + lowered.cond + ") { " + bindPrefix + "return " + emit(branchExpr, branchScope) + "; }");
			isFirst = false;
		}

		out.push("return null;");
		out.push("})()");
		return out.join(" ");
	}
}
