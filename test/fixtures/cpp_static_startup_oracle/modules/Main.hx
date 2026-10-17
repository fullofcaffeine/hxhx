/** References load modules even when the referencing code does not run. */
class Main {
	static var own:Int = initialize();

	static function initialize():Int {
		Sys.println("Main.field");
		return 1;
	}

	static function main():Void {
		Sys.println("main");
	}

	#if dead_call
	static function unused():Void {
		Helper.call();
	}
	#end

	#if type_only
	static function unused(value:Helper):Void {}
	#end

	#if deferred_call
	static var callback:Void->Void = function():Void {
		Helper.call();
	};
	#end
}

class Sibling {
	public static var value:Int = initialize();

	static function initialize():Int {
		Sys.println("sibling");
		return 1;
	}
}
