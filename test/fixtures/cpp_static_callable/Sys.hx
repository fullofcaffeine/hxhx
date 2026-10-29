/**
	Declare the existing console primitive without loading unrelated standard-library modules.
	Dynamic is the upstream printing boundary: values reach the native output operation unchanged.
 */
extern class Sys {
	public static function println(value:Dynamic):Void;
}
