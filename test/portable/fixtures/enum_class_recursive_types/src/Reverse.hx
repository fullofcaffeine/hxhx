/** The class may appear before the enum that refers back to it. */
class ReverseNode {
	public final link:ReverseLink;

	public function new(link:ReverseLink) {
		this.link = link;
	}

	public function depth():Int {
		return switch (link) {
			case End: 1;
			case More(node): 1 + node.depth();
		};
	}
}

enum ReverseLink {
	End;
	More(node:ReverseNode);
}

/** Provide an entry point for the reverse source-order case. */
class Reverse {
	public static function depth():Int {
		return new ReverseNode(More(new ReverseNode(End))).depth();
	}
}
