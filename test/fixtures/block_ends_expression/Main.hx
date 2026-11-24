/**
	A block ends its expression, as in Haxe 4.3.7: after `if (flag) { ... }`, a line that starts
	with `(` is the next statement, not a call of the block (haxe.macro.Printer.printTypeDefinition).
**/
class Main {
	static function f(flag:Bool, n:Int):String {
		return switch (n) {
			case 0:
				var x = 1;
				if (flag) {
					x = 2;
				}
				(flag ? "a" : "b") + x;
			case _: "z";
		}
	}

	static function main() {
		Sys.println(f(true, 0) + " " + f(false, 0));
	}
}
