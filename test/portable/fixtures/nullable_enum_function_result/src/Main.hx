enum Choice {
	Plain;
	Payload(value:Int);
}

class Picker {
	final useEarlyReturn:Bool;

	public function new(useEarlyReturn:Bool) {
		this.useEarlyReturn = useEarlyReturn;
	}

	public function choose():Null<Choice> {
		if (useEarlyReturn)
			return Payload(7);
		return Plain;
	}
}

class Main {
	static function describe(picker:Picker):String {
		return switch (picker.choose()) {
			case null: "null";
			case Plain: "Plain";
			case Payload(number): 'Payload:$number';
		};
	}

	static function main() {
		Sys.println('early=${describe(new Picker(true))}');
		Sys.println('late=${describe(new Picker(false))}');
	}
}
