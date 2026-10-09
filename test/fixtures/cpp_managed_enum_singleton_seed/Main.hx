/** Observe singleton publication from class startup, field initialization, and main. */
class Main {
	public static var absent:Choice;
	public static var alias:Choice = Choice.Empty;
	public static var atMain:Choice;
	public static var atStartup:Choice;
	public static var empty:Choice = Choice.Empty;
	public static var other:Other = Other.Empty;

	static function __init__():Void {
		atStartup = Choice.Last;
	}

	public static function main():Void {
		atMain = Choice.Last;
	}
}

/** Source order fixes the two distinct constructor tags. */
enum Choice {
	Empty;
	Last;
}

/** Equal constructor names in different enum declarations retain separate identities. */
enum Other {
	Empty;
}
