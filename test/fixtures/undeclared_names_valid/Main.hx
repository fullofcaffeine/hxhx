import haxe.ds.Option;
import haxe.Json.parse;
import haxe.macro.Expr.ExprDef;
import haxe.macro.Context;
import does.not.*;
#if nope
import does.not.Exist;
#end

enum Mode {
	Run;
	Build;
}

typedef Alias = Main;

@:native("Math")
extern class NativeMath {
	static function floor(value:Float):Float;
}

class Main {
	public static function hi():String
		return "hi";

	static function main() {
		var mode = Run;
		switch (mode) {
			case Build:
				Sys.println("build");
			case Run:
				Sys.println("run");
		}
		final none:Option<Int> = None;
		Sys.println(none == None);
		var Local = 3;
		Sys.println(Local);
		final c:Class<Dynamic> = Main;
		Sys.println(c != null);
		Sys.println(Alias.hi());
		Sys.println(parse("1"));
		Sys.println(Std.string(Mode.Build));
		Sys.println(ModuleOps.total());
		if (false) {
			untyped Nope.foo();
			untyped Missing;
			Sys.println(NativeMath.floor(1.5));
		}
	}
}
