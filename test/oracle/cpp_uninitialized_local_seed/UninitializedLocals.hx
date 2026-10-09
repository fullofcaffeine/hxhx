/** Assignment changes only the selected lexical slot, including a slot retained by a closure. */
class UninitializedLocals {
	static function main():Void {
		var value:Int;
		value = 7;
		{
			var value:Int;
			value = 11;
			if (value != 11)
				throw "inner assignment failed";
		}
		if (value != 7)
			throw "shadowing changed the outer value";
		value = 13;
		if (value != 13)
			throw "repeated assignment failed";
		var shared:Int;
		shared = 17;
		final read = () -> shared;
		shared = 19;
		if (read() != 19)
			throw "captured assignment lost its location";
	}
}
