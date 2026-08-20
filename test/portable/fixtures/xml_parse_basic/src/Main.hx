class Main {
	static function main() {
		final doc = Xml.parse('<root id="7"><child>hi &amp; bye</child><leaf/></root>');
		final root = doc.firstElement();
		final child = root.firstElement();
		final childText = child.firstChild();

		Sys.println('root=' + root.nodeName + ',id=' + root.get("id"));
		Sys.println('child=' + child.nodeName + ',text=' + childText.nodeValue);
		Sys.println('roundtrip=' + doc.toString());

		// A 20-byte OCaml string occupies three words. Dynamic method lookup must
		// recognize it as text before probing the structural Array carrier.
		final text:Dynamic = "01234567890123456789";
		final cca = Reflect.field(text, "cca");
		Sys.println('dynamic-cca=' + Reflect.callMethod(text, cca, [0]));
	}
}
