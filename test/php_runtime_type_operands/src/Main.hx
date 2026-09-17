/** Two distinct class values used to check PHP's exact runtime type selection. */
class MyClass {}
class OtherClass {}

/** A class-valued switch must distinguish core and user-defined types. */
class Main {
	static function label(value:Class<Dynamic>):String {
		return switch value {
			case String: "String";
			case MyClass: "MyClass";
			case _: "other";
		}
	}

	static function main():Void {
		Sys.println(label(String));
		Sys.println(label(MyClass));
		Sys.println(label(OtherClass));
	}
}
