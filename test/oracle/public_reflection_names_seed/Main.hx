import model.Types;
import model.Types.PublicLeaf as Alias;
import model.Types.PublicEnum;
import model.Types.Renamed;
import model.Types.Specialized;
import model.Types.Ordinary;
import other.Types.PublicLeaf as Right;

/** Independent Haxe 4.3.7 observer for public runtime names and lookup. */
class Main {
	/** Only this observer boundary uses host syntax to print the same lines on JavaScript. */
	static function out(value:String):Void {
		#if js
		js.Syntax.code("console.log({0})", value);
		#else
		Sys.println(value);
		#end
	}

	static function main():Void {
		out(Type.getClassName(Right));
		out(Type.getClassName(Types));
		out(Type.getClassName(Alias));
		out(Type.getClassName(Types.hidden()));
		out(Type.getEnumName(PublicEnum));
		out(Type.getEnumName(Types.hiddenEnum()));
		out(Type.getClassName(Renamed));
		out(Type.getClassName(Type.getClass(new Specialized<Int>(7))));
		out(Type.getClassName(Type.getClass(new Ordinary<Int>(7))));
		out(Std.string(Type.resolveClass("model.PublicLeaf") == Alias));
		out(Std.string(Type.resolveClass("model.Types.PublicLeaf") == null));
		out(Std.string(Type.resolveClass("model.Renamed") == Renamed));
		out(Std.string(Type.resolveClass("RenamedNative") == Renamed));
	}
}
