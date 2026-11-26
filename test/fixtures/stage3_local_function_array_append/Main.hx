enum Tree {
	Leaf(value:Int);
	Node(children:Array<Tree>);
}

/**
	Appends inside block-bodied local functions (haxe_ocaml-hoxig). `Array.map` and `filter` are
	inlined into a loop that appends to the result, as an array comprehension does. Upstream's
	`unit.HelperMacros.pipeMarkupLiteral` has the first shape: a local function `loop` that calls
	`el.map(loop)` in a switch case.
**/
class Main {
	static function main():Void {
		function total(tree:Tree):Int {
			return switch (tree) {
				case Leaf(value):
					value;
				case Node(children):
					final sums = children.map(total);
					var sum = 0;
					for (part in sums)
						sum += part;
					sum;
			}
		}
		Sys.println(total(Node([Leaf(1), Node([Leaf(2), Leaf(3)]), Leaf(4)])));

		final factor = 3;
		function scaled(values:Array<Int>):Array<Int> {
			final kept = values.filter(value -> value != 2);
			return kept.map(value -> value * factor);
		}
		Sys.println(scaled([1, 2, 3]).join(","));

		function labels(names:Array<String>):Array<String> {
			if (names.length <= 1)
				return [for (name in names) "<" + name + ">"];
			return labels(names.slice(0, 1)).concat(labels(names.slice(1)));
		}
		Sys.println(labels(["a", "b", "c"]).join(""));

		function firstLong(words:Array<String>):String {
			final long = [for (word in words) if (word.length > 2) word.toUpperCase()];
			if (long.length == 0)
				return "none";
			return long[0];
		}
		Sys.println(firstLong(["an", "ox", "bee", "cat"]) + " " + firstLong(["an"]));
	}
}
