class Main {
	static var missing:String;

	static function main() {
		try {
			Sys.println(missing + missing);
		} catch (e:Dynamic) {
			Sys.println("caught:" + e);
		}
	}
}
