/** Each producer retains the conversion for its own element type after erasure. */
class ArrayProducerMain {
	/** Dynamic is the erased-array boundary exercised by this observer. */
	static function text(value:Dynamic):String {
		return Std.string(value);
	}

	static function positive(value:Int):Bool {
		return value > 0;
	}

	static function number(value:Bool):Int {
		return value ? 1 : 0;
	}

	static function keep(value:Bool):Bool {
		return value;
	}

	static function main():Void {
		final empty = new Array<Bool>();
		final alias:Dynamic = empty;
		empty.push(false);
		Sys.println(text(alias));
		final flags = [true, false];
		final copied = flags.copy();
		flags[0] = false;
		Sys.println(text(copied));
		Sys.println(text(flags));
		Sys.println(text(copied.concat(empty)));
		Sys.println(text(copied.slice(1)));
		final vacant = copied.slice(2);
		vacant.push(true);
		Sys.println(text(vacant));
		final numbers = [0, 1];
		final mapped = numbers.map(positive);
		Sys.println(text(mapped));
		Sys.println(text(mapped.map(number)));
		Sys.println(text(mapped.filter(keep)));
		Sys.println(text(flags.splice(0, 1)));
		final removedEmpty = flags.splice(0, 0);
		removedEmpty.push(true);
		Sys.println(text(removedEmpty));
		final filteredEmpty = empty.filter(keep);
		filteredEmpty.push(true);
		Sys.println(text(filteredEmpty));
		final originalEmpty:Array<Bool> = [];
		final copiedEmpty = originalEmpty.copy();
		copiedEmpty.push(false);
		Sys.println(text(copiedEmpty));
		final mixed:Array<Dynamic> = [];
		mixed.push(false);
		mixed.push(0);
		Sys.println(text(mixed));
		mixed[1] = true;
		Sys.println(text(mixed));
		final nullable:Array<Null<Bool>> = [null, false, true];
		Sys.println(text(nullable));
	}
}
