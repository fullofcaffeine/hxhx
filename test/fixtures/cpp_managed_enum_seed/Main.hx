/** Keep enum declarations and payloads observable without an I/O dependency in the source owner. */
class Main {
	public static var empty:Choice = Choice.Empty;
	public static var alias:Choice = Choice.Empty;
	public static var payload:Choice = Choice.Carry([7]);
	public static var absent:Choice;
	public static var other:Other = Other.Empty;
	public static var enumWasNullDuringStartup:Bool;

	static function __init__():Void {
		enumWasNullDuringStartup = Choice.Empty == null;
	}

	public static function main():Void {}
}

/** The two constructors require distinct tags and retain a managed array payload. */
enum Choice {
	Empty;
	Carry(values:Array<Int>);
}

/** A repeated constructor name must not merge two enum declaration identities. */
enum Other {
	Empty;
}
