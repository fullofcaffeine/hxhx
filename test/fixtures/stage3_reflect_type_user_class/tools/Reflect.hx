package tools;

/** A project class that shares its short name with the standard `Reflect`. */
class Reflect {
	public static function hasField(o:Dynamic, name:String):String
		return "project hasField " + name;

	public static function isFunction(o:Dynamic):String
		return "project isFunction";
}
