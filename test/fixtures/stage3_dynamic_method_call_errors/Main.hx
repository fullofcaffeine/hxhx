/**
	The rest calls run natively. Upstream's interpreter stops on them, so they
	cannot be compared with upstream. Every other call below cannot reach a
	method. The program must catch a named error and keep running.
**/
class Box {
	public function new() {}

	public function rest(first:Int, ...more:Int):Int {
		var total = first;
		for (value in more)
			total += value;
		return total;
	}

	public function callRest(other:Dynamic):Int
		return other.rest(1, 2);

	public function add(a:Int, b:Int):Int
		return a + b;

	public function half(value:Float):Float
		return value / 2;

	public function greet(name:String):String
		return "hello " + name;
}

class Main {
	static function report(action:() -> Dynamic):Void {
		try {
			Sys.println(action());
		} catch (error:Dynamic) {
			Sys.println(Std.string(error));
		}
	}

	static function main() {
		final box:Dynamic = new Box();
		report(() -> box.rest(1, 2, 3));
		report(() -> box.rest(1));
		report(() -> new Box().callRest(box));
		report(() -> box.absent());
		report(() -> box.add(1, 2, 3));
		report(() -> box.add(1));
		report(() -> box.half("text"));
		report(() -> box.greet(5));
		final nothing:Dynamic = null;
		report(() -> nothing.pick());
		final plain:Dynamic = {};
		report(() -> plain.absent());
		final text:Dynamic = "hello";
		report(() -> text.absent());
		final notFunction:Dynamic = {value: 5};
		report(() -> notFunction.value());
	}
}
