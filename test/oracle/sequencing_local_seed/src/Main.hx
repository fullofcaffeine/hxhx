/** Discarded effects share authored locals and execute once in source order. */
class Main {
	static function main():Void {
		var counter = 0;
		var tick = function():Void {
			counter = counter + 1;
		};
		var initialized = {
			tick();
			counter + 10;
		};
		var __hxhx_lambda_seq_0 = 4;
		var result = {
			tick();
			counter = counter + 1;
			__hxhx_lambda_seq_0;
		};
		Sys.println(initialized);
		Sys.println(result);
		Sys.println(counter);
	}
}
