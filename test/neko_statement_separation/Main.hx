/** Each assignment must execute after its complete preceding statement. */
class Main {
	static function main():Void {
		var value = 0;
		if (false)
			value = 99;
		value = 1;
		Sys.println(value);
		if (true)
			value = 2
		else
			value = 99;
		value = 3;
		Sys.println(value);
		{
			value = 4;
		}
		value = 5;
		Sys.println(value);
		while (false)
			value = 99;
		value = 6;
		Sys.println(value);
		for (index in 0...1)
			value = index;
		value = 7;
		Sys.println(value);
		switch (value) {
			case 7:
				value = 8;
			default:
				value = 99;
		}
		value = 9;
		Sys.println(value);
		try {
			value = 10;
		} catch (error:String) {
			value = 99;
		}
		value = 11;
		Sys.println(value);
		if (false)
			value = 99;
		(function():Void {
			Sys.println("called");
		})();
	}
}
