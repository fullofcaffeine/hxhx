/**
	A closed user class used to observe exact nominal exception behavior.

	The class deliberately has no superclass, interfaces, generic parameters,
	extern boundary, or dynamic methods.
**/
class Box {
	public var value:Int;

	public function new(value:Int) {
		this.value = value;
	}
}

/** Freezes upstream Haxe 4.3.7 behavior for nominal throw and catch control. */
class Main {
	static function line(value:String):Void {
		#if js
		js.Syntax.code("console.log({0})", value);
		#else
		Sys.println(value);
		#end
	}

	static function throwFresh(value:Int):Void {
		final thrown = new Box(value);
		throw thrown;
	}

	static function directCase():Void {
		final direct = new Box(4);
		final alias = direct;
		try {
			throw direct;
		} catch (_:Int) {
			line("wrong-int");
		} catch (caught:Box) {
			caught.value += 1;
			line("box:" + caught.value);
			line("identity:" + (caught == alias));
		} catch (caught:Dynamic) {
			line(caught == null ? "dynamic:null" : "dynamic:other");
		}
	}

	static function nullCase():Void {
		final value:Box = null;
		try {
			throw value;
		} catch (_:Int) {
			line("wrong-null-int");
		} catch (_:Box) {
			line("wrong-null-box");
		} catch (caught:Dynamic) {
			line(caught == null ? "dynamic:null" : "dynamic:other");
		}
	}

	static function rethrowCase(value:Int):Void {
		try {
			try {
				throwFresh(value);
			} catch (caught:Box) {
				throw caught;
			}
		} catch (caught:Box) {
			caught.value += 10;
			line("rethrow-box:" + caught.value);
		} catch (caught:Dynamic) {
			line(caught == null ? "rethrow-dynamic:null" : "rethrow-dynamic:other");
		}
	}

	static function main():Void {
		directCase();
		nullCase();
		rethrowCase(7);
	}
}
