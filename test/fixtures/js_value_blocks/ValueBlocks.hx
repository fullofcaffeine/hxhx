/** Exercises value blocks followed by comments through both compiler routes. **/
class ValueBlocks {
	static var calls = 0;
	static var order = 0;

	static function tick(value:Int):Int {
		calls++;
		order = order * 10 + value;
		return value;
	}

	static var initial = {
		var value:Int = tick(7);
		value = value * 10 + tick(3);
		value;
	} /** Documentation belongs to the next declaration. */

	static function main():Void {
		Sys.println(initial);
		var local = {
			var value:Int = tick(4);
			value = value * 10 + tick(2);
			value;
		} /* A comment before the local semicolon. */;
		Sys.println(local);
		var record = {value: 9};
		{
			record.value = 8;
		}
		Sys.println(record.value);
		Sys.println(calls);
		Sys.println(order);
	}
}
