package callers;

class Direct {
	static function main():Void {
		var sum = 0;
		for (value in macros.Macros.items())
			sum += value;
	}
}
