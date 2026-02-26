class Main {
	static function main() {
		run("named", '<root>&amp; &lt; &gt;</root>');
		run("numeric", '<root>&#65;&#x42;</root>');
		run("unknown", '<root>&nope;</root>');
		run("unterminated", '<root>&nope</root>');
	}

	static function run(label:String, source:String):Void {
		final doc = Xml.parse(source);
		final root = doc.firstElement();
		final text = root.firstChild();
		Sys.println(label + "=" + text.nodeValue);
		Sys.println(label + "_rt=" + doc.toString());
	}
}
