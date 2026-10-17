/** Observe target defaults before either class finishes static initialization. */
class Main {
	public static var zero:Int;
	public static var flag:Bool;
	public static var text:String;
	public static var number:Null<Int>;
	public static var array:Array<Int>;
	public static var record:{value:Int};
	public static var callback:Void->Int;
	public static var object:Holder;

	/** This is the language's Dynamic default contract, not an implementation escape. */
	public static var erased:Dynamic;

	static function __init__():Void {
		Sys.println(zero);
		Sys.println(flag);
		Sys.println(text == null);
		Sys.println(number == null);
		Sys.println(array == null);
		Sys.println(record == null);
		Sys.println(callback == null);
		Sys.println(object == null);
		Sys.println(erased == null);
	}

	public static function mark(label:String, value:Int):Int {
		Sys.println(label);
		Sys.println(value);
		return value;
	}

	static function main():Void {
		Sys.println(Alpha.first);
		Sys.println(Alpha.second);
		Sys.println(Beta.value);
	}
}

/** A nominal reference whose default is observed without constructing an instance. */
class Holder {}

class Alpha {
	public static var first:Int = Main.mark("Alpha.first", 1);
	public static var second:Int = Main.mark("Alpha.second", Beta.value);
}

class Beta {
	public static var value:Int = Main.mark("Beta.value", Alpha.first + 2);
}
