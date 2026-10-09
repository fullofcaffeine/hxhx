/** Switch-expression arms must retain the loops and exits that the source declares. */
class Main {
	static function main():Void {
		var visits = 0;
		final result = switch (1) {
			case 1:
				var index = 0;
				while (index < 5) {
					index++;
					final value = if (index == 2) {
						continue;
					} else {
						index;
					};
					if (value == 4)
						break;
					visits++;
				}
				"selected";
			default:
				visits += 100;
				"wrong";
		};
		Sys.println(result);
		Sys.println(visits);
		var calls = 0;
		final choose = function(value:Int):String {
			final selected = switch (value) {
				case 0: return "early";
				default:
					calls++;
					"late";
			};
			return selected;
		};
		Sys.println(choose(0));
		Sys.println(choose(1));
		Sys.println(calls);
		final collect = function():Int {
			var index = 0;
			var total = 0;
			while (index < 4) {
				index++;
				final selected = switch (index) {
					case 1: continue;
					case 3: break;
					default: index;
				};
				total += selected;
			}
			return total;
		};
		Sys.println(collect());
	}
}
