/**
	A closed user class used to observe a runtime class value crossing a throw
	whose static Haxe type is `Dynamic`.
**/
class Box {
	public var value:Int;

	public function new(value:Int) {
		this.value = value;
	}
}

/** Freezes upstream Haxe 4.3.7 behavior for Dynamic throw transport. */
class Main {
	static function line(value:String):Void {
		#if js
		js.Syntax.code("console.log({0})", value);
		#else
		Sys.println(value);
		#end
	}

	static function throwDynamic(value:Dynamic):Void {
		throw value;
	}

	static function intCase():String {
		try {
			throwDynamic(41);
		} catch (caught:Int) {
			return "int=" + caught;
		} catch (_:Dynamic) {
			return "int=dynamic";
		}
		return "int=miss";
	}

	static function boolCase():String {
		try {
			throwDynamic(true);
		} catch (_:Int) {
			return "bool=wrong-int";
		} catch (caught:Bool) {
			return "bool=" + caught;
		} catch (_:Dynamic) {
			return "bool=dynamic";
		}
		return "bool=miss";
	}

	static function stringCase():String {
		try {
			throwDynamic("boom");
		} catch (caught:String) {
			return "string=" + caught;
		} catch (_:Dynamic) {
			return "string=dynamic";
		}
		return "string=miss";
	}

	static function nullCase():String {
		final value:Dynamic = null;
		try {
			throwDynamic(value);
		} catch (_:String) {
			return "null=wrong-string";
		} catch (_:Box) {
			return "null=wrong-box";
		} catch (_:Dynamic) {
			return "null=dynamic";
		}
		return "null=miss";
	}

	static function boxCase():String {
		final box = new Box(5);
		final alias = box;
		try {
			throwDynamic(box);
		} catch (_:Int) {
			return "box=wrong-int";
		} catch (caught:Box) {
			caught.value += 1;
			return "box=" + caught.value + "|identity=" + (caught == alias);
		} catch (_:Dynamic) {
			return "box=dynamic";
		}
		return "box=miss";
	}

	static function rethrowCase():String {
		try {
			try {
				throwDynamic(41);
			} catch (caught:Dynamic) {
				throw caught;
			}
		} catch (caught:Int) {
			return "rethrow=" + (caught + 1);
		} catch (_:Dynamic) {
			return "rethrow=dynamic";
		}
		return "rethrow=miss";
	}

	static function main():Void {
		line([intCase(), boolCase(), stringCase(), nullCase(), boxCase(), rethrowCase()].join(","));
	}
}
