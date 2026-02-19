class Main {
	static function main() {
		var i = 0;
		var sum = 0;

		while (true) {
			i++;
			if (i == 2)
				continue;
			if (i == 5)
				break;
			sum += i;
		}

		if (i != 5)
			throw "bad i";
		if (sum != 8)
			throw "bad sum";

		var outer = 0;
		var innerCount = 0;
		while (outer < 3) {
			outer++;
			var inner = 0;
			while (true) {
				inner++;
				innerCount++;
				if (inner == 2)
					break;
			}
		}

		if (innerCount != 6)
			throw "bad innerCount";
		Sys.println("OK loop_control");
	}
}
