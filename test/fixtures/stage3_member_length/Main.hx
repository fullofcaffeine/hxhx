typedef NS = Null<String>;

class Box {
	public var text:String;
	public var items:Array<Int>;
	public var label:Null<String>;

	public function new(text:String) {
		this.text = text;
		this.items = [1, 2, 3, 4];
		this.label = null;
	}

	public function shout():String {
		return text + "!";
	}
}

class Main {
	static var title:String = "static";
	static var names:Array<String> = ["a", "b"];

	static function maybe(present:Bool):Null<String> {
		return present ? "yes" : null;
	}

	static function maybeAlias(present:Bool):NS {
		return present ? "alias" : null;
	}

	static function maybeList(present:Bool):Null<Array<Int>> {
		return present ? [7, 8] : null;
	}

	static function main():Void {
		final box = new Box("hello");
		Sys.println(box.text.length);
		Sys.println(box.items.length);
		Sys.println(title.length);
		Sys.println(names.length);
		Sys.println(Main.title.length);

		final text = "a=1;bb=22;c=3";
		Sys.println(text.split(";")[1].split("=")[1].length);
		final parts = text.split(";");
		Sys.println(parts[0].length);
		final grid = [[1, 2], [3, 4, 5]];
		Sys.println(grid[1].length);

		Sys.println(maybe(true).length);
		Sys.println(maybeList(true).length);
		Sys.println(maybeAlias(true).length);
		final local:Null<String> = maybe(true);
		Sys.println(local.length);

		final dynamicText:Dynamic = "dynamic";
		Sys.println((dynamicText : String).length);

		final s = box.shout();
		Sys.println(s.substr(1).length);
		Sys.println(box.shout().substr(1).length);

		try {
			Sys.println(maybe(false).length);
			Sys.println("unreachable");
		} catch (e:Dynamic) {
			Sys.println("caught null string length");
		}
		try {
			Sys.println(maybeList(false).length);
			Sys.println("unreachable");
		} catch (e:Dynamic) {
			Sys.println("caught null array length");
		}
		try {
			Sys.println(box.label.length);
			Sys.println("unreachable");
		} catch (e:Dynamic) {
			Sys.println("caught null field length");
		}
		try {
			final missing:Null<String> = maybe(false);
			Sys.println(missing.length);
			Sys.println("unreachable");
		} catch (e:String) {
			// The message text differs by target (upstream eval says "field
			// access on null"; native says "Null Access"), so print only that
			// a String-typed catch selected it.
			Sys.println("caught as String");
		} catch (e:Dynamic) {
			Sys.println("caught as Dynamic");
		}
		try {
			Sys.println(maybeAlias(false).length);
			Sys.println("unreachable");
		} catch (e:Dynamic) {
			Sys.println("caught null alias length");
		}
	}
}
