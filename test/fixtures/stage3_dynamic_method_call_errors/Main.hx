/**
	Each call below cannot reach a method natively. The program must catch a
	named error and keep running, rather than stop with a crash.
**/
class Box {
	public function new() {}

	public function generic<T>(value:T):T
		return value;

	public function rest(first:Int, ...more:Int):Int
		return first;

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
		report(() -> box.generic(1));
		report(() -> box.rest(1, 2));
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
