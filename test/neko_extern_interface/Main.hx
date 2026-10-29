interface ThroughExtern {}
extern interface Marker extends ThroughExtern {}
interface Ordinary {}

class Container implements Marker implements Ordinary {
	public function new() {}
}

class Main {
	static function main():Void {
		Sys.println(Marker == null);
		Sys.println(Type.getClassName(Marker));
		var value = new Container();
		Sys.println(value is Marker);
		Sys.println(value is Ordinary);
		Sys.println(value is ThroughExtern);
	}
}
