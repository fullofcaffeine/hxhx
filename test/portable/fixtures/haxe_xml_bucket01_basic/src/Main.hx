import haxe.xml.Parser;
import haxe.xml.Check;
import haxe.xml.Access;
import haxe.xml.Fast;
import haxe.xml.Printer;
import haxe.xml.Check.Attrib;
import haxe.xml.Check.Filter;
import haxe.xml.Check.Rule;

class Main {
	static function main() {
		final document = Parser.parse("<root><item id=\"1\">A</item><item id=\"2\">B</item></root>");
		final access = new Access(document);
		final root = access.node.root;
		if (root.name != "root") {
			throw "haxe.xml.Access returned unexpected root";
		}
		Sys.println("haxe.xml.Access=ok");

		final itemRule = Rule.RNode("item", [Attrib.Att("id", Filter.FInt)], Rule.RData());
		final rootRule = Rule.RNode("root", [], Rule.RList([itemRule, itemRule], true));
		Check.checkNode(root.x, rootRule);
		Sys.println("haxe.xml.Check=ok");

		final fast = new Fast(document);
		if (fast.node.root.name != "root") {
			throw "haxe.xml.Fast returned unexpected root";
		}
		Sys.println("haxe.xml.Fast=ok");

		final reparsed = Parser.parse(Printer.print(document, false));
		if (reparsed.firstElement().nodeName != "root") {
			throw "haxe.xml.Parser produced unexpected root";
		}
		Sys.println("haxe.xml.Parser=ok");

		final printed = Printer.print(document, false);
		if (printed.length == 0) {
			throw "haxe.xml.Printer returned empty output";
		}
		Sys.println("haxe.xml.Printer=ok");

		Sys.println("haxe.xml.bucket01=done");
	}
}
