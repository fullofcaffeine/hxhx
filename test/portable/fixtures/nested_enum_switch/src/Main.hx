enum Kw {
	KTrue;
	KFalse;
	KNull;
}

enum Tok {
	TKeyword(k:Kw);
	TOther(c:Int);
}

class Main {
	static function eval(t:Tok):String {
		return switch (t) {
			case TKeyword(k):
				switch (k) {
					case KTrue: "t";
					case KFalse: "f";
					case KNull: "n";
				}
			case TOther(_):
				"other";
		}
	}

	static function main() {
		Sys.println("true=" + eval(TKeyword(KTrue)));
		Sys.println("false=" + eval(TKeyword(KFalse)));
		Sys.println("null=" + eval(TKeyword(KNull)));
		Sys.println("other=" + eval(TOther(1)));
		Sys.println("OK nested_enum_switch");
	}
}

