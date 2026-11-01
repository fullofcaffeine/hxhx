/** A payload-carrying enum whose cases are refined by guards. */
enum Shape {
	Circle(radius:Int);
	Rect(width:Int, height:Int);
	Group(items:Array<Shape>);
}

/**
	A failed guard must fall through to the next case whose pattern matches.
	Guards run only after their pattern matches, at most once per attempt.
 */
class Main {
	static var log:Array<String> = [];

	/** Record that a guard ran, then return its decision. */
	static function check(label:String, result:Bool):Bool {
		log.push(label);
		return result;
	}

	static function flush():Void {
		Sys.println(log.join(","));
		log = [];
	}

	static function enumGuard(shape:Shape):String {
		return switch shape {
			case Circle(r) if (r > 10): "big circle";
			case Circle(r): "circle " + r;
			case Rect(w, h) if (w == h): "square " + w;
			case Rect(w, _) if (w > 100): "wide";
			case Rect(_, _): "rect";
			case Group([Circle(r)]) if (r == 0): "dot group";
			case Group([first, _]) if (enumGuard(first) == "rect"): "rect pair";
			case Group(items): "group " + items.length;
		};
	}

	static function constantGuard(value:Int, limit:Int):String {
		return switch value {
			case 1 if (limit > 1): "one under limit";
			case 1 | 2 if (limit > 0): "small";
			case 3 if (limit < 0): "three";
			default: "other";
		};
	}

	static function arrayGuard(values:Array<Int>):String {
		return switch values {
			case [a, b] if (a > b): "descending";
			case [a, b] if (a == b): "flat " + a;
			case [a, _]: "ascending from " + a;
			case _: "length " + values.length;
		};
	}

	static function objectGuard(point:{x:Int, y:Int}):String {
		return switch point {
			case {x: 0, y: y} if (y > 0): "on positive y axis";
			case {x: x, y: 0} if (x > 0): "on positive x axis";
			case {x: x, y: y} if (x == y): "diagonal";
			case _: "elsewhere";
		};
	}

	/** Guards read locals captured from the enclosing function, including updated values. */
	static function capturedGuard():Void {
		var threshold = 5;
		final classify = (value:Int) -> switch value {
			case v if (v > threshold): "above " + threshold;
			case _: "not above " + threshold;
		};
		Sys.println(classify(7));
		threshold = 9;
		Sys.println(classify(7));
	}

	/** Guards run in source order, only for matching patterns, and stop at the first success. */
	static function sideEffects():Void {
		final result = switch Rect(2, 3) {
			case Circle(_) if (check("circle", true)): "circle";
			case Rect(w, _) if (check("rect-a", w > 5)): "rect-a";
			case Rect(_, h) if (check("rect-b", h == 3)): "rect-b";
			case Rect(_, _) if (check("rect-c", true)): "rect-c";
			case _: "none";
		};
		Sys.println(result);
		flush();
		var calls = 0;
		final total = switch [1, 2] {
			case [a, b] if ({
				calls++;
				a + b > 10;
			}): -1;
			case [a, b] if ({
				calls++;
				a < b;
			}): a + b;
			case _: 0;
		};
		Sys.println(total + " after " + calls + " guards");
	}

	/** A statement switch with no matching guard runs no case body. */
	static function statementGuard(value:Int):Void {
		switch value {
			case v if (check("even", v % 2 == 0)):
				Sys.println("even " + v);
			case v if (check("big", v > 10)):
				Sys.println("big odd " + v);
			case _:
		}
		flush();
	}

	static function main():Void {
		Sys.println(enumGuard(Circle(12)));
		Sys.println(enumGuard(Circle(3)));
		Sys.println(enumGuard(Rect(4, 4)));
		Sys.println(enumGuard(Rect(200, 1)));
		Sys.println(enumGuard(Rect(2, 1)));
		Sys.println(enumGuard(Group([Circle(0)])));
		Sys.println(enumGuard(Group([Circle(1)])));
		Sys.println(enumGuard(Group([Rect(1, 2), Circle(1)])));
		Sys.println(enumGuard(Group([Circle(1), Circle(2)])));
		Sys.println(constantGuard(1, 2));
		Sys.println(constantGuard(1, 1));
		Sys.println(constantGuard(2, 1));
		Sys.println(constantGuard(2, 0));
		Sys.println(constantGuard(3, -1));
		Sys.println(constantGuard(3, 1));
		Sys.println(arrayGuard([3, 1]));
		Sys.println(arrayGuard([2, 2]));
		Sys.println(arrayGuard([1, 2]));
		Sys.println(arrayGuard([1, 2, 3]));
		Sys.println(objectGuard({x: 0, y: 4}));
		Sys.println(objectGuard({x: 0, y: -4}));
		Sys.println(objectGuard({x: 4, y: 0}));
		Sys.println(objectGuard({x: -4, y: -4}));
		Sys.println(objectGuard({x: 1, y: 2}));
		capturedGuard();
		sideEffects();
		statementGuard(4);
		statementGuard(13);
		statementGuard(7);
	}
}
