/**
	The Stage3 OCaml part of the enum-match fixture: Int and String payloads (the Stage3 emitter has
	no Float enum payloads), with matches in statement and expression position.
**/
enum Shape {
	Circle(radius:Int);
	Rect(width:Int, height:Int);
	Labeled(label:String, shape:Shape);
}

class Main {
	static var calls = 0;

	static function next():Shape {
		calls++;
		return Rect(calls, 0);
	}

	static function main() {
		final shape = Labeled("door", Rect(2, 3));
		if (shape.match(Labeled(_, Rect(_, 3))))
			Sys.println("statement");
		final local = shape.match(Circle(_));
		Sys.println(local);
		Sys.println(shape.match(Labeled("door", _)) + " " + next().match(Rect(1, _)) + " " + next().match(Rect(1, _)) + " " + calls);
	}
}
