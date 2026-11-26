/**
	Switch expressions as Haxe 4.3.7 parses them: `ESwitch(subject, cases, default)`, where each case
	has pattern expressions, an optional guard and an optional body. A macro sees the syntax before
	typing.
**/
class Main {
	static function main() {
		final lines = [
			Syntax.show((switch (x) {
				case 1: "one";
				case "s": 2;
				case null: 3;
				case true: 4;
				case -1: 5;
				case 1.5: 6;
				case _: 7;
			})),
			Syntax.show((switch x {
				case A: 1;
				case B(v): v;
				case B(_): 2;
				case C(v, _): v;
				case haxe.ds.Option.Some(o): o;
			})),
			Syntax.show((switch x {
				case A | B: 1;
				case C(v) | D(v): v;
				case(E | F) | G: 2;
			})),
			Syntax.show((switch x {
				case 2, 3: 1;
				case A, B(_): 2;
			})),
			Syntax.show((switch x {
				case v if (v > 1): v;
				case B(w) if (w == 0): w;
			})),
			Syntax.show((switch x {
				case [a, b]: a;
				case [1, _]: 1;
				case []: 0;
			})),
			Syntax.show((switch x {
				case {name: n, age: 3}: n;
				case {}: "";
			})),
			Syntax.show((switch x {
				case var y: y;
				case a = B(_): a;
			})),
			Syntax.show((switch x {
				case 1: "a";
				default: "b";
			})),
			Syntax.show((switch x {
				case 1:
				case 2 if (y):
				case 3: 4;
			})),
			Syntax.show((switch 1 {
				case 2, 3:
				case 4 if (5):
				case 6:
			}))
		];
		for (line in lines)
			Sys.println(line);
	}
}
