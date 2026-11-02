package shadow;

import haxe.macro.Expr;

/**
	Quotations in package `shadow`, which has its own `Std` class and a sub-package `shadow.haxe`.
	`$v{}` on an Int must call the top-level `Std.string`, and constructors must name the top-level
	`haxe.macro.Expr`.
**/
class PackageQuotes {
	public static function operation():Expr {
		final label = shadow.haxe.Marker.label;
		return macro $i{label} + 2;
	}

	public static function value():Expr {
		final n = 7;
		return macro $v{n};
	}
}
