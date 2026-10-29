/** Independent native method-call observations; no upstream implementation is consumed. */
class PushProbe {
	static var events = '';
	static var selected:Array<String> = ['original'];

	static function receiver():Array<String> {
		events += 'r';
		return selected;
	}

	static function value():String {
		events += 'v';
		selected = ['replacement'];
		return 'appended';
	}

	static function main():Void {
		final original = selected;
		final length = receiver().push(value());
		Sys.println('result:' + length + ':' + events + ':' + original.join(',') + ':' + selected[0]);
		events = '';
		receiver().push(value());
		Sys.println('discarded:' + events);
		final flags:Array<Bool> = [];
		Sys.println('empty:' + flags.push(true) + ':' + flags[0]);
		final mixed:Array<Dynamic> = [true];
		// Dynamic is confined to the explicit erased-array recovery boundary.
		final erased:Dynamic = mixed;
		final recovered:Array<Bool> = erased;
		Sys.println('alias:' + recovered.push(false) + ':' + mixed.length + ':' + mixed[1]);
	}
}
