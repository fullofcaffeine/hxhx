class Main {
	static function main():Void {
		try {
			throw 1;
		} catch (_:Dynamic) {
			Sys.println("dynamic");
		} catch (_:Int) {
			Sys.println("int");
		}
	}
}
