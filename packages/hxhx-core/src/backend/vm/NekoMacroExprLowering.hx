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
		final builder = new NekoMacroExprBuilder(fallback);
		var exprDef = builder.macroExprDef(expr);
		if (wrappers != null) {
			var i = wrappers.length;
			while (i > 0) {
				i--;
				exprDef = switch (wrappers[i]) {
					case "parenthesis":
						builder.macroEnum("EParenthesis", [builder.macroExprObject(exprDef)]);
					case "untyped":
						builder.macroEnum("EUntyped", [builder.macroExprObject(exprDef)]);
					case _:
						exprDef;
				}
			}
		}
		return builder.render(builder.macroExprObject(exprDef));
	}
}

class NekoMacroExprBuilder {
	final fallback:HxExpr->String;
	final statements:Array<String>;
	var nextObjectId:Int = 0;

	public function new(fallback:HxExpr->String) {
		this.fallback = fallback;
		this.statements = [];
	}

	public function render(root:String):String {
		final parts = ["(function() {"];
		for (statement in statements)
			parts.push(statement);
		parts.push("return " + root + "; })()");
		return parts.join(" ");
	}

	public function macroExprObject(exprDef:String):String {
		return anonObject(["expr", "pos"], [exprDef, "null"]);
	}

	public function macroExprDef(expr:HxExpr):String {
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
				macroEnum("EField", [macroExprObject(macroExprDef(receiver)), quote(field)]);
			case ENullSafeField(receiver, field):
				macroEnum("EField", [macroExprObject(macroExprDef(receiver)), quote(field), macroEnum("Safe", [])]);
			case EArrayAccess(receiver, index):
				macroEnum("EArray", [macroExprObject(macroExprDef(receiver)), macroExprObject(macroExprDef(index))]);
			case EArrayDecl(values):
				final items = values == null ? [] : [for (value in values) macroExprObject(macroExprDef(value))];
				macroEnum("EArrayDecl", ["$array(" + items.join(", ") + ")"]);
			case EBinop("in", left, right):
				macroEnum("EBinop", [
					macroEnum("OpIn", []),
					macroExprObject(macroExprDef(left)),
					macroExprObject(macroExprDef(right))
				]);
			case EBinop("=>", left, right):
				macroEnum("EBinop", [
					macroEnum("OpArrow", []),
					macroExprObject(macroExprDef(left)),
					macroExprObject(macroExprDef(right))
				]);
			case ECall(EIdent("__hxhx_macro_if"), args):
				final cond = args.length > 0 ? args[0] : HxExpr.EBool(false);
				final thenExpr = args.length > 1 ? args[1] : HxExpr.ENull;
				final elseExpr = if (args.length > 2) {
					switch (args[2]) {
						case EIdent("__hxhx_macro_missing_else"):
							"null";
						case other:
							macroExprObject(macroExprDef(other));
					}
				} else {
					"null";
				}
				macroEnum("EIf", [
					macroExprObject(macroExprDef(cond)),
					macroExprObject(macroExprDef(thenExpr)),
					elseExpr
				]);
			case ECall(callee, args):
				final loweredArgs = args == null ? [] : [for (arg in args) macroExprObject(macroExprDef(arg))];
				macroEnum("ECall", [macroExprObject(macroExprDef(callee)), "$array(" + loweredArgs.join(", ") + ")"]);
			case EUntyped(inner):
				macroEnum("EUntyped", [macroExprObject(macroExprDef(inner))]);
			case EUnop(op, fixity, inner):
				HxUnaryOperatorTools.requireValidFixity(op, fixity);
				macroEnum("EUnop", [
					macroEnum(HxUnaryOperatorTools.macroConstructor(op), []),
					fixity == HxUnaryFixity.Postfix ? "true" : "false",
					macroExprObject(macroExprDef(inner))
				]);
			case _:
				macroEnum("EConst", [macroEnum("CIdent", [quote(fallback(expr))])]);
		}
	}

	public function macroEnum(name:String, params:Array<String>):String {
		return anonObject(["__hx_ctor", "__hx_index", "__hx_params"], [quote(name), "0", "$array(" + (params == null ? "" : params.join(", ")) + ")"]);
	}

	function anonObject(fieldNames:Array<String>, fieldValues:Array<String>):String {
		final tmp = "__hxhx_macro_o" + nextObjectId++;
		statements.push("var " + tmp + " = $new(null);");
		final count = fieldNames.length < fieldValues.length ? fieldNames.length : fieldValues.length;
		for (i in 0...count)
			statements.push(tmp + "." + safeIdent(fieldNames[i]) + " = " + fieldValues[i] + ";");
		return tmp;
	}

	function quote(value:String):String {
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

	function safeIdent(name:String):String {
		if (name == null || name.length == 0)
			return "_";
		return ~/[^A-Za-z0-9_]/g.replace(name, "_");
	}
}
