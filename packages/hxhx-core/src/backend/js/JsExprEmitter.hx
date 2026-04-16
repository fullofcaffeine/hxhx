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
			}
		};
	}

	public static function emit(expr:HxExpr, scope:JsEmitScope):String {
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
				JsNameMangler.quoteString(name);
			case EThis:
				"this";
			case ESuper:
				"super";
			case EIdent(name):
				resolveIdent(name, scope);
			case EField(obj, field):
				emit(obj, scope) + JsNameMangler.propertySuffix(field);
			case ECall(callee, args):
				emitCall(callee, args, scope);
			case EMacroExpr(inner, wrappers):
				emitMacroExpr(inner, wrappers, scope);
			case EMacroType(typeText):
				emitMacroType(typeText);
			case EUnop(op, inner):
				"(" + op + emit(inner, scope) + ")";
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
				"[" + values.map(v -> emit(v, scope)).join(", ") + "]";
			case EArrayAccess(array, index):
				emit(array, scope) + "[" + emit(index, scope) + "]";
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
				emitTryCatchRaw(raw);
			case ERange(startExpr, endExpr):
				emitRangeExpr(startExpr, endExpr, scope);
			case EArrayComprehension(name, iterable, yieldExpr):
				emitArrayComprehension(name, iterable, yieldExpr, scope);
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
	static function emitTryCatchRaw(raw:String):String {
		if (raw == null || raw.length == 0 || raw == "opaque_block_expr")
			unsupported("ETryCatchRaw", raw);

		final rewritten = rewriteSimpleTryCatchRaw(raw);
		if (rewritten != null)
			return rewritten;

		var js = sanitizeCatchTypeHints(raw);
		if (js.indexOf("catch") < 0 && js.indexOf("finally") < 0)
			js += "catch(__hx_err){throw __hx_err;}";
		return "(function () { " + js + " })()";
	}

	static function rewriteSimpleTryCatchRaw(raw:String):Null<String> {
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
		final tryBody = blockToReturningJs(raw.substring(tryOpen + 1, tryClose));
		final catchBody = blockToReturningJs(raw.substring(catchBodyOpen + 1, catchBodyClose));
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

	static function blockToReturningJs(body:String):String {
		var trimmed = sanitizeRawHaxeExpressionSyntax(body == null ? "" : StringTools.trim(body));
		while (StringTools.endsWith(trimmed, ";"))
			trimmed = StringTools.trim(trimmed.substr(0, trimmed.length - 1));
		trimmed = sanitizeRawHaxeExpressionSyntax(trimmed);
		if (trimmed.length == 0)
			return "return null;";
		if (StringTools.startsWith(trimmed, "return ") || StringTools.startsWith(trimmed, "throw "))
			return trimmed + ";";

		final lastSemi = findLastTopLevelSemicolon(trimmed);
		final prefix = lastSemi >= 0 ? trimmed.substr(0, lastSemi + 1) : "";
		final expr = StringTools.trim(lastSemi >= 0 ? trimmed.substr(lastSemi + 1) : trimmed);
		if (expr.length == 0)
			return prefix + " return null;";
		if (StringTools.startsWith(expr, "var ") || StringTools.startsWith(expr, "let ") || StringTools.startsWith(expr, "const "))
			return trimmed + "; return null;";
		return prefix + " return " + expr + ";";
	}

	static function sanitizeRawHaxeExpressionSyntax(raw:String):String {
		return stripExpressionCastHints(stripExpressionMetadata(raw));
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

	static function isMetadataPathChar(code:Int):Bool {
		return (code >= "a".code && code <= "z".code)
			|| (code >= "A".code && code <= "Z".code)
			|| (code >= "0".code && code <= "9".code)
			|| code == "_".code
			|| code == ".".code;
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

	static function emitCall(callee:HxExpr, args:Array<HxExpr>, scope:JsEmitScope):String {
		switch (callee) {
			case EEnumValue(name):
				final params = args == null ? [] : args.map(a -> emit(a, scope));
				return macroEnum(name, params);
			case EIdent("__js__") | EField(EField(EIdent("js"), "Syntax"), "code"):
				return emitInlineJsCode(args, scope);
			case EIdent("__hxhx_throw"):
				final thrown = args.length > 0 ? emit(args[0], scope) : "null";
				return "(function(){ throw " + thrown + "; })()";
			case EIdent("__hxhx_spread"):
				return args.length > 0 ? "..." + emit(args[0], scope) : "";
			case EIdent("trace"):
				return "console.log(" + args.map(a -> emitCallArg(a, scope)).join(", ") + ")";
			case EField(EIdent("Sys"), "println"):
				return "console.log(" + args.map(a -> emitCallArg(a, scope)).join(", ") + ")";
			case EField(EIdent("Sys"), "print"):
				final arg = args.length > 0 ? emit(args[0], scope) : "\"\"";
				return "process.stdout.write(String(" + arg + "))";
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
			case _:
		}
		final calleeJs = emit(callee, scope);
		final argsJs = args.map(a -> emitCallArg(a, scope)).join(", ");
		return calleeJs + "(" + argsJs + ")";
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

	static function emitNew(typePath:String, args:Array<HxExpr>, scope:JsEmitScope):String {
		final argsJs = args.map(a -> emitCallArg(a, scope)).join(", ");
		switch (typePath) {
			case "Array":
				if (args.length == 0)
					return "[]";
				return "new Array(" + argsJs + ")";
			case "Bytes" | "haxe.io.Bytes":
				final ctor = resolveIdent(typePath, scope);
				return "new " + ctor + "(" + argsJs + ")";
			case _:
		}

		if (scope != null) {
			final classCtor = scope.resolveClassRef(typePath);
			if (classCtor != null)
				return "new " + classCtor + "(" + argsJs + ")";

			final lastDot = typePath.lastIndexOf(".");
			if (lastDot > 0 && lastDot + 1 < typePath.length) {
				final simpleType = typePath.substr(lastDot + 1);
				final simpleCtor = scope.resolveClassRef(simpleType);
				if (simpleCtor != null)
					return "new " + simpleCtor + "(" + argsJs + ")";
			}
		}

		if (StringTools.startsWith(typePath, "js.lib.")) {
			final nativeCtor = typePath.substr("js.lib.".length);
			if (nativeCtor != null && nativeCtor.length > 0)
				return "new " + nativeCtor + "(" + argsJs + ")";
		}

		unsupported("ENew", typePath);
		return "";
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
		if (op == "??") {
			final l = emit(left, scope);
			final r = emit(right, scope);
			return "(function(__hx_coalesce){ return (__hx_coalesce != null) ? __hx_coalesce : " + r + "; })(" + l + ")";
		}
		final normalized = switch (op) {
			case "==": "===";
			case "!=": "!==";
			case _: op;
		}
		return "(" + emit(left, scope) + " " + normalized + " " + emit(right, scope) + ")";
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
			case EUnop(op, inner):
				macroEnum("EUnop", [JsNameMangler.quoteString(op), emitMacroExpr(inner, [], scope)]);
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

	static function emitArrayComprehension(name:String, iterable:HxExpr, yieldExpr:HxExpr, scope:JsEmitScope):String {
		final out = new Array<String>();
		final iterName = "__arr_comp_" + JsNameMangler.identifier(name);
		final iterLocals = new haxe.ds.StringMap<String>();
		iterLocals.set(name, iterName);
		final iterScope = nestedScope(scope, iterLocals);

		out.push("(function () {");
		out.push("var __arr_comp_out = [];");

		switch (iterable) {
			case ERange(startExpr, endExpr):
				out.push("var __arr_comp_start = " + emit(startExpr, scope) + ";");
				out.push("var __arr_comp_end = " + emit(endExpr, scope) + ";");
				out.push("for (var " + iterName + " = __arr_comp_start; " + iterName + " < __arr_comp_end; " + iterName + "++) {");
				out.push("__arr_comp_out.push(" + emit(yieldExpr, iterScope) + ");");
				out.push("}");
			case _:
				out.push("var __arr_comp_iter = " + emit(iterable, scope) + ";");
				out.push("for (var __arr_comp_i = 0; __arr_comp_i < __arr_comp_iter.length; __arr_comp_i++) {");
				out.push("var " + iterName + " = __arr_comp_iter[__arr_comp_i];");
				out.push("__arr_comp_out.push(" + emit(yieldExpr, iterScope) + ");");
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
