/**
	Declare the existing console primitive for this focused test.

	The complete standard library is tested separately. Keeping this boundary small
	lets missing imported calls fail independently of standard-library module cycles.
**/
extern class Sys {
	public static function println(value:String):Void;
}
