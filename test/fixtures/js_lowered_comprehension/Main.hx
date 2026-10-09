/** Node's console is the observable boundary for each independently expected Int result. */
@:native("console") extern class Output {
	static function log(value:Int):Void;
}

/** Exercise shared array allocation, loop control, conditional selection, and ordered yields. */
class Main {
	static var effects:Int = 0;

	static function step(value:Int):Int {
		effects = effects * 10 + value;
		return value;
	}

	static function range():Array<Int> {
		return [for (i in step(0)...step(3)) step(i + 4)];
	}

	static function selected(flag:Bool):Array<Int> untyped {
		return flag ? [for (i in 0...3) i * 2] : [];
	}

	static function early():Array<Int> {
		return [
			for (i in 0...3) {
				if (i == 1) return [9];
				i;
			}
		];
	}

	static function observe(values:Array<Int>):Void {
		Output.log(values.length);
		for (i in 0...values.length)
			Output.log(values[i]);
	}

	static function main():Void {
		Main.observe(range());
		Output.log(effects);
		Main.observe(selected(true));
		Main.observe(selected(false));
		final values = [2, 4, 6];
		Main.observe([for (value in values) if (value != 4) value + 1]);
		Main.observe([for (i in 0...2) for (j in 0...2) i * 10 + j]);
		var offset = 5;
		final callback = function():Array<Int> {
			return [for (i in 0...2) i + offset];
		};
		offset = 7;
		Main.observe(callback());
		Main.observe(early());
	}
}
