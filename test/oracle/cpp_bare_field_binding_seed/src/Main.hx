/** A local may share a C++ spelling with an instance field without replacing it. */
class InstanceHolder {
	public var int_:String = "word";

	public function new() {}

	public function value():String {
		var int = 2;
		return Std.string(int) + int_.toUpperCase();
	}

	public function copy():String {
		var int = 2;
		var int_:Int = int;
		return Std.string(int_) + this.int_.toUpperCase();
	}
}

/** Static field selection must retain its owning class across a local collision. */
class StaticHolder {
	public static var int_:String = "word";

	public static function value():String {
		var int = 3;
		return Std.string(int) + int_.toUpperCase();
	}
}

/** Observe both selected fields through ordinary source expressions. */
class Main {
	static function main():Void {
		Sys.println(new InstanceHolder().value());
		Sys.println(StaticHolder.value());
		Sys.println(new InstanceHolder().copy());
	}
}
