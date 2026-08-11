class Main {
	static final STANDALONE_VALUE:Int = {
		var index = 0;
		var total = 0;
		while (index < 6) {
			index++;
			if (index == 2)
				continue;
			if (index == 5)
				break;
			total += index;
		}
		total;
	};

	static function main():Void {
		Sys.println("standalone=" + STANDALONE_VALUE);
	}
}
