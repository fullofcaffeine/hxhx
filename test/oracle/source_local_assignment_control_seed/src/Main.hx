class Main {
	static function choose(early:Bool):Int {
		var value = 1;
		value = {
			if (early)
				return 9;
			3;
		};
		return value;
	}

	static function main():Void {
		var value = 0;
		final assigned = (value = {
			var part = 4;
			part + 3;
		});
		Sys.println(value);
		Sys.println(assigned);
		Sys.println(choose(true));
		Sys.println(choose(false));
		final nested = function():Int {
			var inner = 1;
			inner = {
				return 5;
				99;
			};
			return inner;
		};
		Sys.println(nested());
		var loops = 0;
		while (true) {
			value = {
				loops++;
				break;
				4;
			};
		}
		Sys.println(loops);
		Sys.println(value);
	}
}
