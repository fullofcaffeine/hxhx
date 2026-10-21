import haxe.macro.Expr;

typedef MaybeFieldKind = Null<EFieldKind>;

/** Checks native storage for the optional enum payload used by macro field nodes. */
class Main {
	static var calls:Int = 0;

	static function produce():EFieldKind {
		calls++;
		return Safe;
	}

	static function describe(value:ExprDef):String {
		return switch value {
			case EField(_, "copy", null): "null";
			case EField(_, "copy", Normal): "normal";
			case EField(_, "copy", Safe): "safe";
			case _: "wrong-field";
		};
	}

	static function main():Void {
		final owner:Expr = {expr: EConst(CIdent("receiver")), pos: null};
		Sys.println("constant=" + describe(EField(owner, "copy", Safe)));
		Sys.println("normal=" + describe(EField(owner, "copy", Normal)));
		Sys.println("explicit=" + describe(EField(owner, "copy", null)));
		Sys.println("omitted=" + describe(EField(owner, "copy")));
		final selected:MaybeFieldKind = Safe;
		Sys.println("alias=" + describe(EField(owner, "copy", selected)));
		Sys.println("produced=" + describe(EField(owner, "copy", produce())) + ":calls=" + calls);
	}
}
