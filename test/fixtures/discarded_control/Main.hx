/** Discarding a block result must preserve effects, lexical scope, and abrupt exits. */
class Main {
	static function early(stop:Bool):Int {
		if (true) untyped {
			Sys.println(10);
			if (stop)
				return 11;
			Sys.println(12);
			13;
		}
		return 14;
	}

	static function main():Void {
		var count = 0;
		if (true) untyped {
			count += 1;
			count += 2;
			99;
		};
			(untyped {
				count += 4;
				98;
			});
		untyped ({count += 8; 97;});
		Sys.println(count);
		var used:Int = untyped {
			count += 16;
			count;
		};
		Sys.println(used);
		Sys.println(early(true));
		Sys.println(early(false));
		var index = 0;
		while (index < 5) untyped {
			index += 1;
			if (index == 2)
				continue;
			if (index == 4)
				break;
			Sys.println(index);
			96;
		}
		Sys.println(index);
		if (false) untyped {
			Sys.println(999);
			95;
		}
	}
}
