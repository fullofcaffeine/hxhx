package backend.js;

/**
	Construct quoted syntax through the retained public macro enum declarations.
	This instance owns one emission scope. Constructor order and payload fields
	come from checked declarations, so reflection observes the same representation
	as ordinary enum values. Quoted syntax is data, not executable source.
 */
class JsMacroQuotation {
	final scope:JsEmitScope;

	public function new(scope:JsEmitScope) {
		this.scope = scope;
	}

	public function expression(value:HxExpr, wrappers:Array<String>):String
		return emitMacroExpr(value, wrappers, scope);

	public function type(value:String):String
		return emitMacroType(value);

	function emitMacroExpr(expr:HxExpr, wrappers:Array<String>, scope:JsEmitScope):String {
		var exprDef = macroExprDef(expr, scope);
		if (wrappers != null) {
			var i = wrappers.length;
			while (i > 0) {
				i--;
				exprDef = switch (wrappers[i]) {
					case "untyped":
						macroEnum("EUntyped", [macroExprObject(exprDef)]);
					case _:
						exprDef;
				}
			}
		}
		return macroExprObject(exprDef);
	}

	function emitMacroType(typeText:String):String {
		return macroComplexType(typeText);
	}

	function macroExprObject(exprDef:String):String {
		return "({expr: " + exprDef + ", pos: null})";
	}

	function macroEnum(name:String, params:Array<String>, owner:String = "haxe.macro.Expr.ExprDef"):String {
		if (scope == null || scope.enumDeclarations == null)
			throw "JavaScript macro quotation requires exact retained enum declarations";
		return JsEnumDeclaration.construct(scope.enumDeclarations(owner), name, params);
	}

	function macroConstant(name:String, params:Array<String>):String
		return macroEnum(name, params, "haxe.macro.Expr.Constant");

	function macroTypeEnum(name:String, params:Array<String>):String
		return macroEnum(name, params, "haxe.macro.Expr.ComplexType");

	function macroBinary(name:String, params:Array<String>):String
		return macroEnum(name, params, "haxe.macro.Expr.Binop");

	function macroExprDef(expr:HxExpr, scope:JsEmitScope):String {
		return switch (expr) {
			case EDiscardThen(_, _):
				throw HxMacroBlockBoundary.missingSourceGroup;
			case EString(v):
				macroEnum("EConst", [macroConstant("CString", [JsNameMangler.quoteString(v)])]);
			case EInt(v):
				macroEnum("EConst", [macroConstant("CInt", [JsNameMangler.quoteString(Std.string(v))])]);
			case EFloat(v):
				macroEnum("EConst", [macroConstant("CFloat", [JsNameMangler.quoteString(Std.string(v))])]);
			case ENull:
				macroEnum("EConst", [macroConstant("CIdent", [JsNameMangler.quoteString("null")])]);
			case EIdent(name):
				macroEnum("EConst", [macroConstant("CIdent", [JsNameMangler.quoteString(name)])]);
			case EField(obj, field):
				macroEnum("EField", [emitMacroExpr(obj, [], scope), JsNameMangler.quoteString(field)]);
			case ENullSafeField(obj, field):
				macroEnum("EField", [
					emitMacroExpr(obj, [], scope),
					JsNameMangler.quoteString(field),
					macroEnum("Safe", [], "haxe.macro.Expr.EFieldKind")
				]);
			case EArrayAccess(array, index):
				macroEnum("EArray", [emitMacroExpr(array, [], scope), emitMacroExpr(index, [], scope)]);
			case EArrayDecl(values):
				final items = values == null ? [] : values.map(v -> emitMacroExpr(v, [], scope));
				macroEnum("EArrayDecl", ["[" + items.join(", ") + "]"]);
			case EBinop(op, left, right):
				macroEnum("EBinop", [
					HxMacroBinaryOperator.render(op, macroBinary),
					emitMacroExpr(left, [], scope),
					emitMacroExpr(right, [], scope)
				]);
			case ERange(left, right):
				macroEnum("EBinop", [
					HxMacroBinaryOperator.render("...", macroBinary),
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
				macroEnum("EConst", [macroConstant("CIdent", ["String(" + JsExprEmitter.emit(nameExpr, scope) + ")"])]);
			case ECall(callee, args):
				final loweredArgs = args == null ? [] : args.map(arg -> emitMacroExpr(arg, [], scope));
				macroEnum("ECall", [emitMacroExpr(callee, [], scope), "[" + loweredArgs.join(", ") + "]"]);
			case EUntyped(inner):
				macroEnum("EUntyped", [emitMacroExpr(inner, [], scope)]);
			case EParenthesized(inner, _):
				macroEnum("EParenthesis", [emitMacroExpr(inner, [], scope)]);
			case EUnop(op, fixity, inner):
				HxUnaryOperatorTools.requireValidFixity(op, fixity);
				macroEnum("EUnop", [
					macroEnum(HxUnaryOperatorTools.macroConstructor(op), [], "haxe.macro.Expr.Unop"),
					fixity == HxUnaryFixity.Postfix ? "true" : "false",
					emitMacroExpr(inner, [], scope)
				]);
			case _:
				macroEnum("EConst", [
					macroConstant("CIdent", [JsNameMangler.quoteString(JsExprEmitter.emit(expr, scope))])
				]);
		}
	}

	function macroComplexType(raw:String):String {
		final text = trimLeadingTypeColon(raw);
		final arrowParts = splitTopLevelArrow(text);
		if (arrowParts.length > 1) {
			final args = new Array<String>();
			for (i in 0...arrowParts.length - 1) {
				final segmentArgs = macroFunctionArgTypes(arrowParts[i]);
				for (arg in segmentArgs)
					args.push(arg);
			}
			return macroTypeEnum("TFunction", ["[" + args.join(", ") + "]", macroComplexType(arrowParts[arrowParts.length - 1])]);
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
				return macroTypeEnum("TOptional", [
					macroTypeEnum("TNamed", [JsNameMangler.quoteString(name), macroComplexType(typePart)])
				]);
			}
			return macroTypeEnum("TNamed", [JsNameMangler.quoteString(namePart), macroComplexType(typePart)]);
		}

		if (StringTools.startsWith(trimmed, "?"))
			return macroTypeEnum("TOptional", [macroComplexType(trimmed.substr(1))]);

		final parenEnd = matchingOuterParen(trimmed);
		if (parenEnd == trimmed.length - 1)
			return macroTypeEnum("TParent", [macroComplexType(trimmed.substring(1, trimmed.length - 1))]);

		return macroTypePath(trimmed);
	}

	function macroFunctionArgTypes(raw:String):Array<String> {
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

	function macroTypePath(raw:String):String {
		final path = StringTools.trim(stripGenericTypeParams(raw));
		final parts = path.split(".");
		final name = parts.length == 0 ? path : parts[parts.length - 1];
		final pack = new Array<String>();
		if (parts.length > 1) {
			for (i in 0...parts.length - 1)
				pack.push(JsNameMangler.quoteString(parts[i]));
		}
		final typePath = "{pack: [" + pack.join(", ") + "], name: " + JsNameMangler.quoteString(name) + ", params: [], sub: null}";
		return macroTypeEnum("TPath", [typePath]);
	}

	function trimLeadingTypeColon(raw:String):String {
		var text = StringTools.trim(raw == null ? "" : raw);
		if (StringTools.startsWith(text, ":"))
			text = StringTools.trim(text.substr(1));
		return text;
	}

	function stripGenericTypeParams(raw:String):String {
		final lt = findTopLevelChar(raw, "<".code);
		return lt < 0 ? raw : raw.substr(0, lt);
	}

	function splitTopLevelArrow(raw:String):Array<String> {
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

	function splitTopLevelComma(raw:String):Array<String> {
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

	function findTopLevelChar(raw:String, target:Int):Int {
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

	function matchingOuterParen(raw:String):Int {
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
}
