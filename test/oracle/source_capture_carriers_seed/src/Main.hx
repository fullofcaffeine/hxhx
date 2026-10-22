/** Captured array values and object callbacks must keep their original shared storage. */
class Main {
	static function arrayAlias():Int {
		var values = [1];
		var alias = values;
		alias[0] = 9;
		return values[0];
	}

	static function makeObjectCycle():Void->Int {
		var holder = new CaptureHolder(10);
		function read():Int {
			holder.value++;
			return holder.value;
		}
		holder.callback = read;
		return holder.callback;
	}

	static function main():Void {
		Sys.println(arrayAlias());
		final first = makeObjectCycle();
		final copy = first;
		Sys.println(first());
		Sys.println(copy());
	}
}

/** Creates an object-to-callback-to-object cycle whose callable escapes its creator. */
class CaptureHolder {
	public var value:Int;
	public var callback:Void->Int;

	public function new(value:Int) {
		this.value = value;
	}
}
