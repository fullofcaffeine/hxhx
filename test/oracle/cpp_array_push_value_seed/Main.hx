/** Stored native methods retain their original receiver and ordinary Array.push result. */
class Main {
	static function main():Void {
		var values = [2];
		final original = values;
		final append = values.push;
		Sys.println(append(3));
		Sys.println(append == values.push);
		values = [9];
		Sys.println(append(4));
		Sys.println(original[2]);
		Sys.println(values[0]);
		var effects = 0;
		Sys.println(values.push({effects++; 5;}));
		Sys.println(values[1]);
		Sys.println(effects);
		final callbacks = new Array<Void->Int>();
		final save = callbacks.push;
		Sys.println(save(() -> 7));
		Sys.println(callbacks[0]());
	}
}
