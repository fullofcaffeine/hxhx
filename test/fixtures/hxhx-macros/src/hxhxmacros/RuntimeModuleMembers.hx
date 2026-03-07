package hxhxmacros;

class RuntimeModuleMembers {
	public static function touch():Void {}
}

private class RuntimeModuleHelper {
	public static function ping():String {
		return "ok";
	}
}

enum RuntimeModuleState {
	Ready;
	Busy(code:Int);
}

typedef RuntimeModuleData = {
	final name:String;
}

abstract RuntimeModuleId(String) from String to String {}
