/** Null reference arguments keep the selected method declaration. */
class Main {
	static function arrayValue(value:Array<Int>):Bool
		return value == null;

	static function stringValue(value:String):Bool
		return value == null;

	static function recordValue(value:{name:String}):Bool
		return value == null;

	static function functionValue(value:Void->Void):Bool
		return value == null;

	static function main():Void {
		Sys.println(arrayValue(null));
		Sys.println(stringValue(null));
		Sys.println(recordValue(null));
		Sys.println(functionValue(null));
		Sys.println(stringValue("present"));
	}
}
