/** Class initialization calls another class before ordinary static values are assigned. */
class FeatureStartup {
	public static var value:Int = initialize();

	static function __init__():Void {
		trace("entry:init");
		StartupLater.ping();
	}

	static function initialize():Int {
		trace("entry:field");
		return 3;
	}

	static function main():Void {
		trace(value);
		trace(StartupLater.value);
	}
}

/** Methods must exist during initialization; the field initializer runs once afterward. */
class StartupLater {
	public static var value:Int = initialize();

	static function __init__():Void {
		trace("later:init");
	}

	public static function ping():Void {
		trace("later:method");
	}

	static function initialize():Int {
		trace("later:field");
		return 4;
	}
}
