enum abstract Signal(Int) {
	var Red = 10;
	var Alias = Red;
	var Blue = 20;
}

enum abstract Label(String) {
	var Red = "red";
	var Blue = "blue";
}

enum abstract Flag(Bool) {
	var Yes = true;
	var No = false;
}

class Main {
	static function main():Void {
		Sys.println(Signal.Red);
		Sys.println(Signal.Alias);
		Sys.println(Signal.Blue);
		Sys.println(Label.Red);
		Sys.println(Label.Blue);
		Sys.println(Flag.Yes);
		Sys.println(Flag.No);
	}
}
