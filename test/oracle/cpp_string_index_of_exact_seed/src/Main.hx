/**
	Repo-owned observable contract for String.indexOf receiver and start handling.

	Computed receivers are included because a typed instance call and a direct
	source-shaped call must have the same target behavior.
**/
class Main {
	static function emit(value:String):Void {
		#if js
		js.Syntax.code("console.log({0})", value);
		#else
		Sys.println(value);
		#end
	}

	static function main():Void {
		final text = "haxe-ocaml-haxe";
		emit("computed=" + ("native" + "-target").indexOf("target"));
		emit("local=" + text.indexOf("haxe"));
		emit("missing=" + text.indexOf("other"));
		emit("offset=" + text.indexOf("haxe", 1));
		emit("beyond=" + text.indexOf("haxe", 99));
		emit("empty=" + text.indexOf("", 4));
	}
}
