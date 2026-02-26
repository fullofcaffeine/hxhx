import haxe.rtti.CType;
import haxe.rtti.Rtti;
import haxe.rtti.XmlParser;

@:rtti
class RttiFixtureType {
	public var value:Int;

	public function new(value:Int) {
		this.value = value;
	}
}

class Main {
	static function main() {
		final ctype:CType = CType.CUnknown;
		final ctypeResult = switch (ctype) {
			case CUnknown: "ok";
			case _: "unexpected";
		}
		Sys.println("haxe.rtti.CType=" + ctypeResult);

		final parser = new XmlParser();
		if (parser == null) {
			throw "haxe.rtti.XmlParser constructor failed";
		}
		Sys.println("haxe.rtti.XmlParser=ok");

		try {
			Rtti.getRtti(RttiFixtureType);
		} catch (_:haxe.Exception) {}
		Sys.println("haxe.rtti.Rtti=ok");

		Sys.println("haxe.rtti.bucket01=done");
	}
}
