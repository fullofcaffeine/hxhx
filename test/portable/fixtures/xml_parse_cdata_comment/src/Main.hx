class Main {
	static function main() {
		final doc = Xml.parse('<root><!-- note --><![CDATA[x<y>]]><child>z</child></root>');
		final root = doc.firstElement();
		for (child in root.iterator()) {
			switch (child.nodeType) {
				case Xml.Comment:
					Sys.println("comment=" + child.nodeValue);
				case Xml.CData:
					Sys.println("cdata=" + child.nodeValue);
				case Xml.Element:
					Sys.println("element=" + child.nodeName + ",text=" + child.firstChild().nodeValue);
				case _:
					Sys.println("other=" + child.nodeType);
			}
		}
		Sys.println("rt=" + doc.toString());
	}
}
