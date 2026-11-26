/**
	The switch pattern of `case macro <quoted>:`, as upstream's matcher sees it.

	Why
	- Upstream's parser reifies a quotation wherever it appears, a case pattern included
	  (`parse_macro_expr` ends in `reify_expr`, `src/syntax/grammar.mly` lines 1275-1294 in Haxe
	  4.3.7). The matcher then reads the construction syntax as a pattern, so a splice binds a
	  typed value: `$v{(s:String)}` is `EConst(CString(s))` and binds `s:String`, `$b{el}` is
	  `EBlock(el)` and binds `el:Array<Expr>` (`src/syntax/reification.ml` lines 350-368).
	- hxhx's parser kept such a pattern as an opaque placeholder, so nothing was bound
	  (haxe_ocaml-ikf1n).

	What
	- `pattern` builds upstream's construction syntax with `MacroReificationLowering.exportQuotation`
	  and reads it as a pattern with the existing pattern forms: a record is `PObject`, a constructor
	  call `PEnumExtract`, a bare constructor `PEnumValue`, literals their constant patterns, an
	  array `PArray`, `_` `PWildcard`, and a lowercase name (a splice payload) `PBind`.
	- Position fields (`pos`, `posPath`, `namePos`) are left out of each `PObject`, so they match
	  anything, as upstream's matcher skips them in a reification pattern (`src/typing/matcher.ml`
	  lines 488-499).
	- Anything else, such as `$v{x}` without a written type (upstream writes
	  `Context.makeExpr(x, ...)` there), is not a pattern; `pattern` throws upstream's message,
	  "Unrecognized pattern".
**/
class MacroPatternLowering {
	/** The pattern of `case macro <quoted>:`; `wrappers` are the quote's modifiers (`untyped`). */
	public static function pattern(quoted:HxExpr, wrappers:Array<String>):HxSwitchPattern {
		final root:haxe.macro.Expr.Position = {file: "", min: 0, max: 0};
		final construction = MacroReificationLowering.exportQuotation(quoted, wrappers, new MacroSyntaxPositions("<macro pattern>"), root);
		return switch construction {
			case ECheckType(inner, _): of(inner);
			case other: of(other);
		};
	}

	static function of(expression:HxExpr):HxSwitchPattern {
		return switch expression {
			case EAnon(names, values):
				final kept = [
					for (index in 0...names.length)
						if (!isPositionField(names[index])) index
				];
				PObject([for (index in kept) names[index]], [for (index in kept) of(values[index])]);
			case ECall(EIdent(name), arguments) if (isConstructorName(name)):
				PEnumExtract(name, [for (argument in arguments) of(argument)]);
			case EIdent("_"):
				PWildcard;
			case EIdent(name) if (isConstructorName(name)):
				PEnumValue(name);
			case EIdent(name):
				PBind(name);
			case EString(value, _):
				PString(value);
			case EInt(value):
				PInt(value);
			case EBool(value):
				PBool(value);
			case ENull:
				PNull;
			case EArrayDecl(items):
				PArray([for (item in items) of(item)]);
			case _:
				throw "Unrecognized pattern: " + Std.string(expression);
		};
	}

	static function isPositionField(name:String):Bool
		return name == "pos" || name == "posPath" || name == "namePos";

	static function isConstructorName(name:String):Bool {
		final first = name.charCodeAt(0);
		return first != null && first >= "A".code && first <= "Z".code;
	}
}
