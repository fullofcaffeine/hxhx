import haxe.macro.Expr;

/** An open record whose `expr` field has the wrong type must still be rejected. **/
class Wrong {
	static function main() {
		var func = {args: [], expr: 1}
		Sys.println(FFun(func));
	}
}
