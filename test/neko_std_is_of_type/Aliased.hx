import Std as Runtime;

/** A renamed import retains the selected standard declaration. */
class Aliased {
	public static function check(value:Main.Child):Bool {
		return Runtime.isOfType(value, Main.Parent);
	}
}
