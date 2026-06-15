package backend.vm;

/**
	Small Neko source lowering for expression-position macro quotes.

	Why
	- Upstream-derived Neko gates pass `macro expr` values to runtime helpers such
	  as `haxe.macro.Printer` and switch-pattern probes.
	- Emitting the quoted payload as ordinary Neko source loses the
	  `haxe.macro.Expr` shape and can leak Haxe-only syntax such as `in`.

	What
	- Produces the minimal enum-like object shape used by the current macro quote
	  pressure tests: `__hx_ctor`, `__hx_index`, `__hx_params`, and `{ expr, pos }`.
	- Keeps unsupported quote payloads as neutral macro identifiers rather than
	  emitting target-invalid syntax.
**/
class NekoMacroExprLowering {
	public static function render(expr:HxExpr, wrappers:Array<String>, fallback:HxExpr->String):String {
		var exprDef = macroExprDef(expr, fallback);
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

	static function macroExprObject(exprDef:String):String {
		return anonObject(["expr", "pos"], [exprDef, "null"]);
	}

	static function macroExprDef(expr:HxExpr, fallback:HxExpr->String):String {
		return switch (expr) {
			case EString(value):
				macroEnum("EConst", [macroEnum("CString", [quote(value), macroEnum("DoubleQuotes", [])])]);
			case EInt(value):
				macroEnum("EConst", [macroEnum("CInt", [quote(Std.string(value)), "null"])]);
			case EFloat(value):
				macroEnum("EConst", [macroEnum("CFloat", [quote(Std.string(value)), "null"])]);
			case ENull:
				macroEnum("EConst", [macroEnum("CIdent", [quote("null")])]);
			case EIdent(name):
				macroEnum("EConst", [macroEnum("CIdent", [quote(name)])]);
			case EField(receiver, field):
				macroEnum("EField", [render(receiver, [], fallback), quote(field)]);
			case EArrayAccess(receiver, index):
				macroEnum("EArray", [render(receiver, [], fallback), render(index, [], fallback)]);
			case EArrayDecl(values):
				final items = values == null ? [] : [for (value in values) render(value, [], fallback)];
				macroEnum("EArrayDecl", ["$array(" + items.join(", ") + ")"]);
			case EBinop("in", left, right):
				macroEnum("EBinop", [macroEnum("OpIn", []), render(left, [], fallback), render(right, [], fallback)]);
			case EBinop("=>", left, right):
				macroEnum("EBinop", [macroEnum("OpArrow", []), render(left, [], fallback), render(right, [], fallback)]);
			case ECall(EIdent("__hxhx_macro_if"), args):
				final cond = args.length > 0 ? args[0] : HxExpr.EBool(false);
				final thenExpr = args.length > 1 ? args[1] : HxExpr.ENull;
				final elseExpr = if (args.length > 2) {
					switch (args[2]) {
						case EIdent("__hxhx_macro_missing_else"):
							"null";
						case other:
							render(other, [], fallback);
					}
				} else {
					"null";
				}
				macroEnum("EIf", [render(cond, [], fallback), render(thenExpr, [], fallback), elseExpr]);
			case ECall(callee, args):
				final loweredArgs = args == null ? [] : [for (arg in args) render(arg, [], fallback)];
				macroEnum("ECall", [render(callee, [], fallback), "$array(" + loweredArgs.join(", ") + ")"]);
			case EUntyped(inner):
				macroEnum("EUntyped", [render(inner, [], fallback)]);
			case EUnop(op, inner):
				macroEnum("EUnop", [quote(op), render(inner, [], fallback)]);
			case _:
				macroEnum("EConst", [macroEnum("CIdent", [quote(fallback(expr))])]);
		}
	}

	static function macroEnum(name:String, params:Array<String>):String {
		return anonObject(["__hx_ctor", "__hx_index", "__hx_params"], [quote(name), "0", "$array(" + (params == null ? "" : params.join(", ")) + ")"]);
	}

	static function anonObject(fieldNames:Array<String>, fieldValues:Array<String>):String {
		final tmp = "__hxhx_o";
		final parts = ["(function() { var " + tmp + " = $new(null);"];
		final count = fieldNames.length < fieldValues.length ? fieldNames.length : fieldValues.length;
		for (i in 0...count)
			parts.push(tmp + "." + safeIdent(fieldNames[i]) + " = " + fieldValues[i] + ";");
		parts.push("return " + tmp + "; })()");
		return parts.join(" ");
	}

	static function quote(value:String):String {
		if (value == null)
			return "\"\"";
		var out = "\"";
		for (i in 0...value.length) {
			final c = value.charCodeAt(i);
			out += switch (c) {
				case "\\".code:
					"\\\\";
				case "\"".code:
					"\\\"";
				case "\n".code:
					"\\n";
				case "\r".code:
					"\\r";
				case "\t".code:
					"\\t";
				case _:
					value.charAt(i);
			}
		}
		return out + "\"";
	}

	static function safeIdent(name:String):String {
		if (name == null || name.length == 0)
			return "_";
		return ~/[^A-Za-z0-9_]/g.replace(name, "_");
	}
}
