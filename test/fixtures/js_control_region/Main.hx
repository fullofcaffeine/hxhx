/** Local functions exercise shared control without native syntax or target injection. */
class Main {
	var stored:Int;

	public function new() {
		stored = 13;
	}

	function capture():() -> Int {
		return function():Int {
			return stored;
		};
	}

	static function main():Void {
		var outer = 7;
		function choose(early:Bool):Int {
			var value = 20;
			function inner():Int {
				return value + 2;
			}
			if (early) {
				return inner();
			}
			return value;
		}
		Sys.println(choose(true));
		Sys.println(choose(false));
		Sys.println(outer);
		function scan():Int {
			var n = 0;
			var total = 0;
			while (n < 5) {
				n++;
				if (n == 2)
					continue;
				if (n == 4)
					break;
				total += n;
			}
			return total;
		}
		Sys.println(scan());
		function range():Int {
			for (n in 0...4) {
				if (n == 2)
					return n;
			}
			return -1;
		}
		Sys.println(range());
		function caught():Int {
			try {
				throw "bad";
			} catch (error:String) {
				return error.length;
			}
		}
		Sys.println(caught());
		function shadow():Int {
			var outer = 30;
			{
				var outer = 50;
				Sys.println(outer);
			}
			return outer;
		}
		Sys.println(shadow());
		function repeat():Int {
			var n = 0;
			do {
				n++;
			} while (n < 2);
			return n;
		}
		Sys.println(repeat());
		function branch(n:Int):Int {
			switch (n) {
				case 0:
					return 10;
				default:
					return 11;
			}
		}
		Sys.println(branch(1));
		function update():Void {
			outer = outer + 1;
			return;
		}
		update();
		Sys.println(outer);
		final captured = new Main().capture();
		Sys.println(captured());
	}
}
