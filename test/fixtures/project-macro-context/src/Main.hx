class Main {
	static function main():Void {
		Sys.println(ContextProbe.describe("Main.hx"));
		Sys.println(ContextProbe.inlined());
		Sys.println(ContextProbe.parsed());
	}
}
