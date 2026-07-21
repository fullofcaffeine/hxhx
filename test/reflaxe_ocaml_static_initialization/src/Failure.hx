class Failure {
	public static var before:Int = InitLog.record("Failure.before", 10);
	public static var broken:Int = fail();
	public static var after:Int = InitLog.record("Failure.after", 30);

	static function fail():Int {
		InitLog.events.push("Failure.broken");
		throw "initializer failed";
	}
}
