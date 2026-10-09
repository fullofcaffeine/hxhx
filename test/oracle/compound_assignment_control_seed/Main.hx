/** Right-side mutation cannot replace the saved value of a compound update. */
class Main {
	static function main():Void {
		var value = 2;
		value += {
			value = 10;
			3;
		};
		if (value != 5)
			throw "compound update lost the old value";
		var result = (value *= {
			value = 20;
			2;
		});
		if (result != 10 || value != 10)
			throw "compound update lost its result or writeback";
		var text = "a";
		text += if (true) {
			text = "b";
			"c";
		} else "d";
		if (text != "ac")
			throw "compound concatenation lost the old string";
	}
}
