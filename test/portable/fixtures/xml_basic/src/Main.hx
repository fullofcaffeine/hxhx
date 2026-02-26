class Main {
	static function main() {
		final root = Xml.createElement("root");
		root.set("id", "7");
		root.addChild(Xml.createPCData("hi"));

		final doc = Xml.createDocument();
		doc.addChild(root);

		final first = doc.firstElement();
		final child = first.firstChild();

		Sys.println("name=" + first.nodeName + ",id=" + first.get("id"));
		Sys.println("child=" + child.nodeValue);
		Sys.println("printed=" + doc.toString());
	}
}
