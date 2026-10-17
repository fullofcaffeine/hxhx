/** Literal character codes enter static storage as Int values on every target. */
class Main {
	public static var ascii:Int = "A".code;
	public static var emoji:Int = "\u{1F600}".code;
	public static var escaped:Int = "\u00E9".code;
	public static var maximum:Int = "\u{10FFFF}".code;
	public static var newline:Int = "\n".code;
	public static var nul:Int = "\x00".code;
	public static var octal:Int = "\101".code;
	public static var space:Int = " ".code;

	public static function main():Void {}
}
