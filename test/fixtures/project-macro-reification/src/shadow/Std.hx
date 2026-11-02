package shadow;

/** A same-package type named `Std`: code in package `shadow` that writes `Std` means this class. */
class Std {
	public static function string(value:Dynamic):String
		return "shadowed";
}
