package custom;

/** A same-spelled user method must keep its ordinary call behavior. */
class Std {
	public static function isOfType(value:Main.Child, target:Class<Main.Parent>):Bool {
		Sys.println("custom");
		return false;
	}
}
