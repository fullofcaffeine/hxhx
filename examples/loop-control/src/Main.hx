class Main {
	static function main() {
		var i = 0;
		var sum = 0;

		while (true) {
			i++;
			if (i == 2) continue;
			if (i == 5) break;
			sum += i;
		}

		// i: 1, 2, 3, 4, 5 (but 2 is skipped in sum)
		// sum: 1 + 3 + 4 = 8
		if (i != 5) throw "bad i";
		if (sum != 8) throw "bad sum";

		// Ensure nested `break` only breaks the inner loop.
		var outer = 0;
		var innerCount = 0;
		while (outer < 3) {
			outer++;
			var inner = 0;
			while (true) {
				inner++;
				innerCount++;
				if (inner == 2) break;
			}
		}
		if (innerCount != 6) throw "bad innerCount";

		Sys.println("OK loop-control");
	}
}

