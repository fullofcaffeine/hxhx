class Main {
	static function main() {
		final doc = Xml.parse('<root id="7"><child>hi &amp; bye</child><leaf/></root>');
		final root = doc.firstElement();
		final child = root.firstElement();
		final childText = child.firstChild();

		Sys.println('root=' + root.nodeName + ',id=' + root.get("id"));
		Sys.println('child=' + child.nodeName + ',text=' + childText.nodeValue);
		Sys.println('roundtrip=' + doc.toString());
	}
}
