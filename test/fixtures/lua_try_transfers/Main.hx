/** Exercise method, closure, loop, and catch destinations across native protected calls. */
class Main {
	static function selected(value:Bool):Int {
		try {
			if (value)
				return 3;
			throw "failure";
		} catch (error:String) {
			return 4;
		}
	}

	static function nested():String {
		try {
			try {
				return "nested";
			} catch (error:String) {
				return "wrong";
			}
		} catch (error:String) {
			return "wrong-outer";
		}
	}

	static function emptyReturn():Void {
		try {
			return;
		} catch (error:String) {
			Sys.println("wrong-void");
		}
		Sys.println("wrong-after-void");
	}

	static function nilReturn():Null<String> {
		try {
			return null;
		} catch (error:String) {
			return "wrong-nil";
		}
	}

	static function main():Void {
		Sys.println(selected(true));
		Sys.println(selected(false));
		for (value in [0, 1, 2, 3]) {
			try {
				if (value == 0)
					continue;
				if (value == 2)
					break;
				Sys.println(value);
			} catch (error:String) {
				Sys.println(error);
			}
		}
		Sys.println("after");
		Sys.println(nested());
		emptyReturn();
		try {
			final callback = function():String {
				return "closure";
			};
			Sys.println(callback());
			Sys.println("after-closure");
			for (value in [0, 1, 2]) {
				if (value == 0)
					continue;
				if (value == 2)
					break;
				Sys.println(value);
			}
		} catch (error:String) {
			Sys.println("wrong-closure");
		}
		try {
			try {
				throw true;
			} catch (error:String) {
				Sys.println("wrong-type");
			}
		} catch (error:Bool) {
			Sys.println(error);
		}
		try {
			throw new ChildFailure();
		} catch (error:String) {
			Sys.println("wrong-class");
		} catch (error:BaseFailure) {
			Sys.println(error.message());
		}
		var index = 0;
		while (index < 3) {
			index = index + 1;
			try {
				if (index == 1)
					continue;
				if (index == 3)
					break;
				Sys.println("while:" + index);
			} catch (error:String) {
				Sys.println("wrong-while");
			}
		}
		var remaining = 0;
		do {
			remaining = remaining + 1;
			try {
				if (remaining == 1)
					continue;
				if (remaining == 2)
					break;
			} catch (error:String) {
				Sys.println("wrong-do");
			}
		} while (remaining < 4);
		Sys.println("do:" + remaining);
		Sys.println(nilReturn() == null);
		Sys.println("finished");
	}
}

/** Ordinary thrown objects retain their exact declared class identity. */
class BaseFailure {
	public function new() {}

	public function message():String {
		return "class-catch";
	}
}

/** A child thrown value must satisfy the parent catch without a source-name match. */
class ChildFailure extends BaseFailure {}
