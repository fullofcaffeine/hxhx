/** Both parser-created sequences must preserve authored names and execute effects once. */
class Main {
	static var counter:Int = 0;
	static var initialized:Int = {
		tick();
		counter + 10;
	};

	static function value():Int {
		var __hxhx_lambda_seq_0 = 4;
		var result = {
			tick();
			counter = counter + 1;
			__hxhx_lambda_seq_0;
		};
		return result;
	}

	/** Discarding this result must not require a value of type Void. */
	static function tick():Void {
		counter = counter + 1;
	}

	static function main():Void {
		Sys.println(initialized);
		Sys.println(value());
		Sys.println(counter);
	}
}
