class StatementMain {
	static function choose(flag:Bool):Int {
		var value = 1;
		value = if (flag) 9 else 3;
		return value;
	}

	static function exit(flag:Bool):Int {
		var value = 1;
		value = {
			if (flag)
				return 11;
			12;
		};
		return value;
	}

	static function main():Void {
		Sys.println(choose(true));
		Sys.println(choose(false));
		Sys.println(exit(true));
		Sys.println(exit(false));
	}
}
