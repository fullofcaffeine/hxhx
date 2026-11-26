import haxe.macro.Expr;

/**
	Type quotations as Haxe 4.3.7 parses them: `macro : T` becomes an expression that builds the
	`ComplexType` value, so these functions run outside a macro context too.
**/
class Main {
	static function plain():ComplexType {
		return macro :Int;
	}

	static function nullable(t:ComplexType):ComplexType
		return macro :Null<$t>;

	static function spliced(t:ComplexType):ComplexType {
		return macro :$t;
	}

	static function nested():ComplexType {
		return macro :Array<Map<String, Int>>;
	}

	static function subType():ComplexType {
		return macro :haxe.macro.Expr.ComplexType;
	}

	static function replaced(tp:TypePath):ComplexType {
		return macro :$tp<Bool>;
	}

	static function functions():Array<ComplexType> {
		return [
			macro :Int->String,
			macro :(Int, ?String) -> Void,
			macro :(a:Int, b:Float) -> Bool,
			macro :(?Int) -> Void
		];
	}

	static function others():Array<ComplexType> {
		return [macro :(Int), macro :Main & Printer];
	}

	static function main() {
		final printer = new haxe.macro.Printer();
		final all = [
			plain(),
			nullable(plain()),
			spliced(nested()),
			subType(),
			replaced({pack: ["haxe", "ds"], name: "Option", params: []})
		].concat(functions()).concat(others());
		Sys.println([for (t in all) printer.printComplexType(t)].join("\n"));
	}
}

typedef Printer = haxe.macro.Printer;
