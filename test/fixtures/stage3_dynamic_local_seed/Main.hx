/** Dynamic locals must keep value categories across initialization, writes, and control results. */
class Main {
	static var initialized:Dynamic = {
		var stored:Dynamic = observe(true);
		stored = false;
		stored;
	};
	static var total:Dynamic = {
		var stored:Dynamic = 2;
		stored += amount();
		stored;
	};

	static function observe(value:Bool):Bool {
		Sys.println("observed");
		return value;
	}

	static function erase(value:Dynamic):Dynamic {
		return value;
	}

	static function amount():Int {
		Sys.println("amount");
		return 5;
	}

	static function collision():Dynamic {
		var __hx_storage_left = 2;
		var __hx_storage_right = 3;
		var result:Dynamic = 3;
		result += __hx_storage_left + __hx_storage_right;
		return result;
	}

	static function select(flag:Bool):Dynamic {
		return if (flag) {
			var result:Dynamic = observe(true);
			result;
		} else {
			var result:Dynamic = "other";
			result;
		};
	}

	static function main():Void {
		Sys.println(initialized);
		Sys.println(initialized == 0);
		Sys.println(total);
		var value:Dynamic = observe(true);
		Sys.println(value);
		Sys.println(value == 1);
		value = 7;
		Sys.println(value);
		value += amount();
		Sys.println(value);
		value = observe(false);
		Sys.println(value);
		Sys.println(value == 0);
		var copied:Dynamic = erase(value);
		Sys.println(copied);
		var negated:Bool = !value;
		Sys.println(negated);
		copied = !value;
		Sys.println(copied);
		if (!value)
			Sys.println("not branch");
		else
			Sys.println("wrong branch");
		Sys.println(!value ? "yes" : "no");
		Sys.println("not:" + !value);
		value = "text";
		value += 7;
		Sys.println(value);
		value = null;
		Sys.println(value);
		Sys.println(select(true));
		Sys.println(select(false));
		Sys.println(collision());
	}
}
