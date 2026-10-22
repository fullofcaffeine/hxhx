/** This ordinary application used to build, then abort during native Map.set dispatch. */
class Normal {
	static function main():Void {
		final values:Map<String, Bool> = [];
		values.set("value", true);
		Sys.println(values.get("value"));
	}
}
