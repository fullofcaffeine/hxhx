class Main {
	static function main() {
		var x = 0;
		while (x < 3) {
			x = x + 1;
		}

		switch (x) {
			case 3:
				x = 4;
			default:
				x = 5;
		}

		var y = switch (x) {
			case 0: 10;
			case 1, 2: 20;
			default: 30;
		};
		x = y;
	}
}
