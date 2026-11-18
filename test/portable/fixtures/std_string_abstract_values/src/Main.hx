enum abstract Mime(String) {
	var Json = "application/json";
	var Text = "text/plain";
}

abstract Scheme(String) {
	public inline function new(value:String)
		this = value;
}

enum abstract Code(Int) {
	var NotFound = 404;
}

abstract Flag(Bool) {
	public inline function new(value:Bool)
		this = value;
}

abstract Ratio(Float) {
	public inline function new(value:Float)
		this = value;
}

enum abstract Toggle(Bool) {
	var On = true;
	var Off = false;
}

abstract Tagged<T>(T) from T to T {}

abstract Named(String) {
	public inline function new(value:String)
		this = value;

	public function toString():String
		return "named:" + this;
}

class Main {
	static function main() {
		Sys.println("mime=" + Std.string(Json));
		Sys.println("scheme=" + Std.string(new Scheme("https")));
		Sys.println("code=" + Std.string(NotFound));
		Sys.println("flag=" + Std.string(new Flag(true)));
		Sys.println("ratio=" + Std.string(new Ratio(1.5)));
		final maybe:Null<Mime> = Text;
		Sys.println("nullable=" + Std.string(maybe));
		final missing:Null<Mime> = null;
		Sys.println("missing=" + Std.string(missing));
		final maybeCode:Null<Code> = NotFound;
		Sys.println("nullable code=" + Std.string(maybeCode));
		Sys.println("named=" + Std.string(new Named("x")));
		final on:Null<Toggle> = On;
		final off:Null<Toggle> = Off;
		Sys.println("toggle=" + Std.string(on) + "," + Std.string(off) + " interpolated=" + '$on');
		final flag:Null<Flag> = new Flag(false);
		Sys.println("nullable flag=" + Std.string(flag));
		final tagged:Tagged<Int> = 5;
		final taggedText:Tagged<String> = "five";
		Sys.println("tagged=" + Std.string(tagged) + "," + Std.string(taggedText));
	}
}
