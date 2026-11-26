import haxe.macro.Expr;

/**
	A block that starts with a type quotation, as Haxe 4.3.7 parses it: `macro` is a keyword, so
	`{ macro : Dynamic; }` is a block, not an object literal with a field named `macro`.
**/
class Main {
	static function pick(t:Null<ComplexType>):ComplexType {
		return if (t == null) {
			macro :Dynamic;
		} else {
			t;
		}
	}

	static function statement(t:Null<ComplexType>):ComplexType {
		var result = t;
		if (t == null) {
			macro :Dynamic;
			result = macro :Bool;
		}
		return result;
	}

	static function object():{name:Int} {
		return {name: 1};
	}

	static function main() {
		final printer = new haxe.macro.Printer();
		Sys.println(printer.printComplexType(pick(null)) + " " + printer.printComplexType(pick(macro :Int)) + " "
			+ printer.printComplexType(statement(null)) + " " + object().name);
	}
}
