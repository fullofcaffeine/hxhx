/** A recursive record must remain usable through allocation, field reads, and calls. */
typedef Node = {
	final value:Int;
	final ?next:Node;
};

/** Recursion through a collection must keep the element's declared type. */
typedef Branches = Array<Branches>;

/** Each call returns another callable with the same argument contract. */
typedef Step = Int->Step;

class Main {
	static function step(value:Int):Step {
		js.Syntax.code("console.log({0})", value);
		return step;
	}

	static function sum(node:Node):Int {
		return node.value + (node.next == null ? 0 : sum(node.next));
	}

	static function main():Void {
		final chain:Node = {value: 2, next: {value: 3, next: {value: 5}}};
		js.Syntax.code("console.log({0})", sum(chain));
		js.Syntax.code("console.log({0})", chain.next.next.value);
		final branches:Branches = [[]];
		branches[0].push([]);
		js.Syntax.code("console.log({0})", branches[0].length);
		final next:Step = step;
		next(7)(9);
	}
}
