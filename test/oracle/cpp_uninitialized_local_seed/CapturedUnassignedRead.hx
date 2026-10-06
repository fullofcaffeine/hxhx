/** Native cells retain an unassigned state even when a closure can reach them. */
class CapturedUnassignedRead {
	static function main():Void {
		var value:Int;
		final read = () -> value;
		if (read() != 7)
			throw "unassigned capture became a value";
	}
}
