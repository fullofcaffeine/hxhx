/** Loop control inside a value group must reach the surrounding authored loop. */
class Main {
	static function main():Void {
		var index = 0;
		while (index < 5) {
			index++;
			final selected = if (index == 2) {
				continue;
			} else if (index == 4) {
				break;
			} else {
				"keep";
			};
			Sys.println(selected + index);
		}
		var outer = 0;
		while (outer < 2) {
			outer++;
			var inner = 0;
			while (inner < 3) {
				inner++;
				final selected = if (inner == 1) {
					continue;
				} else if (inner == 3) {
					break;
				} else {
					"inner";
				};
				Sys.println(selected + outer);
			}
			Sys.println("outer" + outer);
		}
		Sys.println("end");
	}
}
