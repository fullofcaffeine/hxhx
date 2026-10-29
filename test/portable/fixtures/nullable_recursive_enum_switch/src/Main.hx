/** Payload constructors exercise recursive matching through nullable call arguments. */
enum Node {
	Wrapped(child:Node, label:String);
	Leaf(value:Int);
	Held(cell:Cell);
	Empty;
}

/** Mutable payloads make accidental copying observable after matching. */
class Cell {
	public var value:Int;

	public function new(value:Int) {
		this.value = value;
	}
}

/** A finite traversal must preserve the child variant, payload, and null sentinel. */
class Main {
	static var visits:Int = 0;
	static var productions:Int = 0;

	static function total(node:Null<Node>, fuel:Int):Int {
		visits++;
		if (fuel == 0)
			return -1000;
		if (node == null)
			return 0;
		return switch (node) {
			case Wrapped(child, _): total(child, fuel - 1);
			case Leaf(value): value;
			case Held(cell): cell.value;
			case Empty: 0;
		};
	}

	static function observe(label:String, node:Null<Node>):Void {
		visits = 0;
		final result = total(node, 8);
		Sys.println(label + "=" + result + ":visits=" + visits);
	}

	static function produce(node:Null<Node>):Null<Node> {
		productions++;
		return node;
	}

	static function updatePayload(node:Null<Node>):Void {
		switch (node) {
			case Held(cell):
				cell.value = 23;
			case _:
				throw "expected a mutable payload";
		}
	}

	static function main():Void {
		observe("null", null);
		observe("empty", Empty);
		observe("leaf", Leaf(7));
		observe("nested", Wrapped(Wrapped(Leaf(11), "inner"), "outer"));
		final selected = switch (produce(Leaf(13))) {
			case Leaf(value): value;
			case _: -1;
		};
		Sys.println("produced=" + selected + ":calls=" + productions);
		final cell = new Cell(19);
		updatePayload(Held(cell));
		Sys.println("payload=" + cell.value);
	}
}
