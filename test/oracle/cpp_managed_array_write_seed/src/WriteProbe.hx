/** Observe native indexed assignment without importing compiler implementation. */
class WriteProbe {
	static var events = '';
	static var selected = [1];
	static var original = selected;

	static function receiver():Array<Int> {
		events += 'r';
		return selected;
	}

	static function index():Int {
		events += 'i';
		selected = [9];
		return 2;
	}

	static function value():Int {
		events += 'v';
		return 7;
	}

	static function negative():Int {
		events += 'n';
		return -1;
	}

	static function main():Void {
		final assigned = receiver()[index()] = value();
		Sys.println(events + ':' + assigned + ':' + original.length + ':' + original.join(',') + ':' + selected[0]);
		events = '';
		receiver()[index()] = value();
		Sys.println('discarded:' + events);
		events = '';
		try {
			final result = original[negative()] = value();
			Sys.println('negative:' + events + ':' + result + ':' + original.length + ':' + original.join(','));
		} catch (_:haxe.Exception) {
			Sys.println('negative:caught:' + events);
		}
		final flags:Array<Bool> = [true];
		flags[3] = true;
		Sys.println('bool:' + flags.join(','));
		final words:Array<String> = ['a'];
		words[2] = 'b';
		Sys.println('string:' + words.length + ':' + (words[1] == null));
		// Dynamic is the explicit erased-array boundary under observation.
		final mixed:Array<Dynamic> = [true];
		final erased:Dynamic = mixed;
		final view:Array<Bool> = erased;
		view[3] = true;
		Sys.println('dynamic:' + mixed.length + ':' + (mixed[1] == null) + ':' + view[1] + ':' + mixed[3]);
		Sys.println('dynamic-gap:' + Std.isOfType(mixed[1], Bool) + ':' + Std.isOfType(mixed[1], Int) + ':' + mixed[1]);
	}
}
