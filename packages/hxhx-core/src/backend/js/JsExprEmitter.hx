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
		var trimmed = body == null ? "" : StringTools.trim(body);
		while (StringTools.endsWith(trimmed, ";"))
			trimmed = StringTools.trim(trimmed.substr(0, trimmed.length - 1));
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
			case EIdent("__js__") | EField(EField(EIdent("js"), "Syntax"), "code"):
				return emitInlineJsCode(args, scope);
			case EIdent("trace"):
				return "console.log(" + args.map(a -> emit(a, scope)).join(", ") + ")";
			case EField(EIdent("Sys"), "println"):
				return "console.log(" + args.map(a -> emit(a, scope)).join(", ") + ")";
			case EField(EIdent("Sys"), "print"):
				final arg = args.length > 0 ? emit(args[0], scope) : "\"\"";
				return "process.stdout.write(String(" + arg + "))";
			case _:
		}
		final calleeJs = emit(callee, scope);
		final argsJs = args.map(a -> emit(a, scope)).join(", ");
		return calleeJs + "(" + argsJs + ")";
	}

	static function emitInlineJsCode(args:Array<HxExpr>, scope:JsEmitScope):String {
		if (args.length == 0)
			return "undefined";
		return switch (args[0]) {
			case EString(code):
				code;
			case _:
				emit(args[0], scope);
		}
	}

	static function emitNew(typePath:String, args:Array<HxExpr>, scope:JsEmitScope):String {
		final argsJs = args.map(a -> emit(a, scope)).join(", ");
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

	static function emitBinop(op:String, left:HxExpr, right:HxExpr, scope:JsEmitScope):String {
		if (op == "??") {
			final l = emit(left, scope);
			final r = emit(right, scope);
			return "((" + l + " != null) ? " + l + " : " + r + ")";
		}
		final normalized = switch (op) {
			case "==": "===";
			case "!=": "!==";
			case _: op;
		}
		return "(" + emit(left, scope) + " " + normalized + " " + emit(right, scope) + ")";
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
			if (lowered.bindName != null) {
				final locals = new haxe.ds.StringMap<String>();
				final bindSafe = "__sw_bind_" + JsNameMangler.identifier(lowered.bindName);
				locals.set(lowered.bindName, bindSafe);
				branchScope = nestedScope(scope, locals);
				bindPrefix = "var " + bindSafe + " = __sw; ";
			}

			out.push(head + " (" + lowered.cond + ") { " + bindPrefix + "return " + emit(branchExpr, branchScope) + "; }");
			isFirst = false;
		}

		out.push("return null;");
		out.push("})()");
		return out.join(" ");
	}
}
