import haxe.macro.Expr;

/** Quotes must retain Array's factory even without an ordinary array or class-value expression. */
class Main {
	static final block:Expr = macro {};
	static final path:ComplexType = macro :demo.Widget;

	final call:Expr = macro missing();

	public function new() {}

	static function main():Void {
		switch block.expr {
			case EBlock(items):
				Sys.println(items.length);
				Sys.println(items.push(macro 7));
			case _:
				throw "unexpected block";
		}
		switch path {
			case TPath(value):
				Sys.println(value.pack.join("."));
				Sys.println(value.params.length);
			case _:
				throw "unexpected type path";
		}
		switch new Main().call.expr {
			case ECall(_, arguments):
				Sys.println(arguments.length);
				Sys.println(arguments.push(macro 9));
			case _:
				throw "unexpected call";
		}
	}
}
