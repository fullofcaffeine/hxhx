import haxe.macro.Expr;

class Main {
	#if macro
	static function shape(e:Expr):String {
		return switch e.expr {
			case EMeta(m, e): "meta(" + m.name + "," + shape(e) + ")";
			case EBinop(op, a, b): Std.string(op) + "(" + shape(a) + "," + shape(b) + ")";
			case EConst(CIdent(name)): name;
			case EConst(CInt(value, _)): value;
			case ETernary(c, a, b): "ternary(" + shape(c) + "," + shape(a) + "," + shape(b) + ")";
			case EParenthesis(e): "paren(" + shape(e) + ")";
			case EUnop(op, post, e): Std.string(op) + "(" + post + "," + shape(e) + ")";
			case _: throw "unexpected syntax";
		}
	}
	#end

	macro static function inspect():Expr {
		for (source in [
			"@:privateAccess a = b + c",
			"@:privateAccess a + b",
			"@:privateAccess @:privateAccess a = b ? c : d",
			"@:privateAccess a = b ? c : d",
			"++@:privateAccess a",
			"@:privateAccess a++",
			"(@:privateAccess a) = b"
		]) {
			Sys.println(source + "\t" + shape(haxe.macro.Context.parse(source, haxe.macro.Context.currentPos())));
		}
		return macro null;
	}

	static function main():Void {
		inspect();
	}
}
