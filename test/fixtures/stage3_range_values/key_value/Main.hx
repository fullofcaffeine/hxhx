/** Standard intervals supply values, not a key/value iterator protocol. */
class Main {
	static function main():Void {
		for (key => value in 1...4)
			trace(key + value);
	}
}
