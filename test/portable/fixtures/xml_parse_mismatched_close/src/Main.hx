class Main {
	static function main() {
		run("mismatch", '<root><a></root>');
		run("stray", '<root></a></root>');
		run("eof", '<root><a>');
	}

	static function run(label:String, source:String):Void {
		try {
			Xml.parse(source);
			Sys.println(label + "=ok");
		} catch (error:Dynamic) {
			Sys.println(label + "=" + Std.string(error));
		}
	}
}
