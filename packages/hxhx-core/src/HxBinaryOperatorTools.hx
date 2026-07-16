/**
	Shared facts about source-written binary operator tokens.

	`HxExpr.EBinop` intentionally keeps its source token during this migration.
	This helper centralizes the semantic classification needed by the abstract
	operator catalog and lowerer without teaching a backend which declaration to
	select.
**/
class HxBinaryOperatorTools {
	public static function isCompoundAssignment(op:String):Bool {
		return switch (op) {
			case "+=" | "-=" | "*=" | "/=" | "%=" | "<<=" | ">>=" | ">>>=" | "&=" | "|=" | "^=": true;
			case _: false;
		};
	}

	public static function baseOperator(op:String):Null<String> {
		return switch (op) {
			case "+=": "+";
			case "-=": "-";
			case "*=": "*";
			case "/=": "/";
			case "%=": "%";
			case "<<=": "<<";
			case ">>=": ">>";
			case ">>>=": ">>>";
			case "&=": "&";
			case "|=": "|";
			case "^=": "^";
			case _: null;
		};
	}

	/** Operators that Haxe abstracts may declare through binary `@:op`. **/
	public static function isAbstractOverloadable(op:String):Bool {
		return switch (op) {
			case "+" | "-" | "*" | "/" | "%" | "<<" | ">>" | ">>>" | "&" | "|" | "^" | "==" | "!=" | "<" | "<=" | ">" | ">=" | "+=" | "-=" | "*=" | "/=" |
				"%=" | "<<=" | ">>=" | ">>>=" | "&=" | "|=" | "^=":
				true;
			case _:
				false;
		};
	}

	/** Equality remains legal for abstract values without an explicit overload. **/
	public static function permitsOrdinaryAbstractFallback(op:String):Bool
		return op == "==" || op == "!=";
}
