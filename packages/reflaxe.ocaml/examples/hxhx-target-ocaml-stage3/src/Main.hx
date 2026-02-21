class Main {
	static function main() {
		var sum = 0;
		for (n in [1, 2, 3, 4]) {
			sum += n;
		}

		Sys.println("native-reflaxe-stage3=ok");
		Sys.println("sum=" + sum);
	}
}
