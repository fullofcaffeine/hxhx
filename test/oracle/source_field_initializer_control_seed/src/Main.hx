class Main {
	static var shared = {
		var value = 2;
		function next():Int {
			while (value < 4) {
				value++;
				if (value == 3)
					continue;
				break;
			}
			return value;
		}
		next;
	};

	var callback = function(value:Int):Int {
		return value + 1;
	};

	public function new() {}

	static function main() {
		Sys.println(shared());
		Sys.println(shared());
		Sys.println(new Main().callback(6));
	}
}
