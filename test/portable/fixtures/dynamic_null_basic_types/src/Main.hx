typedef MaybeDynamic = Null<Dynamic>;

class Main {
	static function emptyValue():Dynamic
		return null;

	static function main() {
		final missing:Dynamic = emptyValue();
		final asInt:Int = missing;
		final asFloat:Float = missing;
		final asBool:Bool = missing;
		Sys.println("int=" + asInt + " float=" + asFloat + " bool=" + asBool);
		final present:Dynamic = 7;
		final presentInt:Int = present;
		final flag:Dynamic = true;
		final presentBool:Bool = flag;
		final ratio:Dynamic = 2.5;
		final presentFloat:Float = ratio;
		Sys.println("present int=" + presentInt + " float=" + presentFloat + " bool=" + presentBool);
		final whole:Dynamic = 1;
		final widened:Float = whole;
		Sys.println("int as float=" + (widened + 0.5));
		final aliased:MaybeDynamic = null;
		final aliasedInt:Int = aliased;
		Sys.println("typedef null=" + aliasedInt);
	}
}
