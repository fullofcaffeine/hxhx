import haxe.macro.Expr;

/**
	Quotations written where the code declares the names `haxe`, `Std`, and `hxhxmacrohost`, plus a
	module whose package has its own `Std` class (`shadow.PackageQuotes`) and one with an import alias
	named `Std` (`AliasQuotes`).

	Upstream builds a quotation's tree inside the compiler, so a local, parameter, or field with one
	of those names does not change what `macro ...` returns. A splice payload with such a name still
	reads the user's binding. `Probe` prints each result in both compilers.
**/
class Shadowing {
	public static function cases():Array<Expr> {
		return [
			ShadowingFields.quote(),
			local(),
			parameters(1, 2.5, "x"),
			values(),
			payloads(),
			shadow.PackageQuotes.value(),
			shadow.PackageQuotes.operation(),
			AliasQuotes.value()
		];
	}

	static function local():Expr {
		var haxe = 42;
		haxe++;
		return macro 1 + 2;
	}

	static function parameters(haxe:Int, Std:Float, hxhxmacrohost:String):Expr
		return macro f(2, "two");

	/** `$v{}` writes `Std.string` and the support module; local names must not capture either. */
	static function values():Expr {
		final Std = 5;
		final hxhxmacrohost = 1.5;
		final some:Null<Int> = 3;
		final names = ["a", "b"];
		return macro [$v{Std}, $v{hxhxmacrohost}, $v{some}, $v{names}];
	}

	static function payloads():Expr {
		final haxe = "named";
		final Std = macro 3;
		final hxhxmacrohost = [macro 4, macro 5];
		return macro g($i{haxe}, $Std, $a{hxhxmacrohost});
	}
}

/** Static fields with the same names. Upstream's own `$v{}` refers to `haxe`, so this class quotes no values. */
class ShadowingFields {
	static var haxe = 7;
	static var Std = 8;
	static var hxhxmacrohost = 9;

	public static function quote():Expr
		return macro h(haxe + Std + hxhxmacrohost);
}
