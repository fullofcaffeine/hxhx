enum Link {
	Last;
	Next(node:Node);
}

/** An enum payload and its owning class field form one recursive type group. */
class Node {
	public final link:Link;

	public function new(link:Link) {
		this.link = link;
	}

	public function depth():Int {
		return switch (link) {
			case Last: 1;
			case Next(node): 1 + node.depth();
		};
	}
}

/** Exercise enum-first, class-first, and acyclic dependencies through generated code. */
class Main {
	static function main():Void {
		Sys.println(new Node(Next(new Node(Last))).depth());
		Sys.println(Reverse.depth());
		Sys.println(Acyclic.value());
	}
}
