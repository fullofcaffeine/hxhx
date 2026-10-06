enum Choice {
	Empty;
	Pair(number:Int, flag:Bool);
	Last;
	Text(value:String);
	Wrap(value:Choice);
	Maybe(value:Null<Choice>);
}

enum Other {
	Empty;
	Pair(number:Int);
}

class Main {
	static function read(value:Choice):Int {
		return switch value {
			case Empty: 1;
			case Pair(number, flag): flag ? number : -number;
			case Last: 2;
			case Text("yes"): 3;
			case Wrap(Pair(number, true)): number + 100;
			case Wrap(Empty): 4;
			case Maybe(null): 5;
			case Maybe(Pair(number, true)): number + 200;
			case _: 0;
		};
	}

	static function other(value:Other):Int {
		return switch value {
			case Empty: 10;
			case Pair(number): number;
			case _: 0;
		};
	}

	static function number():Int {
		Sys.println("number");
		return 9;
	}

	static function flag():Bool {
		Sys.println("flag");
		return false;
	}

	static function main():Void {
		Sys.println(read(Choice.Empty));
		Sys.println(read(Choice.Pair(7, true)));
		Sys.println(read(Choice.Pair(8, false)));
		Sys.println(read(Choice.Last));
		Sys.println(read(Choice.Text("yes")));
		Sys.println(read(Choice.Text("no")));
		Sys.println(read(Choice.Wrap(Choice.Pair(5, true))));
		Sys.println(read(Choice.Wrap(Choice.Pair(5, false))));
		Sys.println(read(Choice.Wrap(Choice.Empty)));
		Sys.println(read(Choice.Pair(number(), flag())));
		Sys.println(Type.enumIndex(Choice.Empty));
		Sys.println(Type.enumIndex(Choice.Pair(0, false)));
		Sys.println(Type.enumIndex(Choice.Last));
		Sys.println(Type.enumIndex(Choice.Text("index")));
		Sys.println(Type.enumIndex(Choice.Wrap(Choice.Empty)));
		Sys.println(read(Choice.Maybe(null)));
		Sys.println(read(Choice.Maybe(Choice.Pair(6, true))));
		Sys.println(read(Choice.Maybe(Choice.Pair(6, false))));
		Sys.println(other(Other.Empty));
		Sys.println(other(Other.Pair(12)));
	}
}
