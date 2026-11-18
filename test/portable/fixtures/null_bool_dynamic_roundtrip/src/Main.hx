class Main {
	static function yesNo(b:Bool):String
		return b ? "T" : "F";

	static function main() {
		final nb:Null<Bool> = true;
		final d:Dynamic = nb;
		final back:Null<Bool> = d;
		Sys.println("roundtrip=" + yesNo(back == true));
		final dynamicFalse:Dynamic = false;
		final castBack:Null<Bool> = cast dynamicFalse;
		Sys.println("cast=" + yesNo(castBack == false));
		Sys.println("equal=" + (d == nb));
	}
}
