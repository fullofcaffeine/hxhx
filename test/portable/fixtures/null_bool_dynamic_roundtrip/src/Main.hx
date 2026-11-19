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
		final map = new Map<String, Dynamic>();
		map.set("nullable", nb);
		Sys.println("map nullable=" + (map.get("nullable") == true));
		final plain:Bool = true;
		map.set("plain", plain);
		Sys.println("map plain=" + (map.get("plain") == true));
	}
}
