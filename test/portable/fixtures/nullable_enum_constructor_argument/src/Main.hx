import haxe.macro.FixtureChoice;
import haxe.macro.FixtureEnvelope;
import haxe.macro.FixtureChoice.Payload;
import haxe.macro.FixtureChoice.Plain;
import haxe.macro.FixtureEnvelope.Wrapped;

class Main {
	static function choose(present:Bool):Null<FixtureChoice> {
		return present ? Payload(7) : null;
	}

	static function rebuildValue(value:FixtureChoice):FixtureChoice {
		return switch (value) {
			case Plain: Plain;
			case Payload(number): Payload(number);
		};
	}

	static function rebuild(value:Null<FixtureChoice>):Null<FixtureChoice> {
		if (value == null)
			return null;
		return rebuildValue(value);
	}

	static function wrap(present:Bool):FixtureEnvelope {
		return Wrapped(rebuild(choose(present)));
	}

	static function describe(value:FixtureEnvelope):String {
		return switch (value) {
			case Wrapped(null): "null";
			case Wrapped(Plain): "Plain";
			case Wrapped(Payload(number)): 'Payload:$number';
		};
	}

	static function main() {
		Sys.println('present=${describe(wrap(true))}');
		Sys.println('missing=${describe(wrap(false))}');
	}
}
