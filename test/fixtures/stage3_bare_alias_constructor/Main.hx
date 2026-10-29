/**
	Bare generic alias constructor paths, including the standard `Map` alias
	that `Xml` itself constructs with `new Map()`. A constructor path may omit
	every alias argument; each omitted binder is inferred once, wherever the
	alias body repeats it.
 */
class Couple<A, B> {
	public final first:A;
	public final second:B;

	public function new(first:A, second:B) {
		this.first = first;
		this.second = second;
	}
}

typedef Pair<T> = Couple<T, T>;

class Main {
	static function main() {
		final pair = new Pair(1, 2);
		Sys.println(pair.first + pair.second);
		final names:Map<String, Int> = new Map();
		names.set("a", 3);
		Sys.println(names.get("a"));
		final parsed = Xml.parse("<root><child id=\"a\"/></root>");
		final root = parsed.firstElement();
		Sys.println(root.nodeName);
		Sys.println(root.firstElement().get("id"));
		final node = Xml.createElement("node");
		node.set("kind", "leaf");
		Sys.println(node.nodeName);
		Sys.println(node.get("kind"));
		Sys.println(node.exists("missing"));
	}
}
