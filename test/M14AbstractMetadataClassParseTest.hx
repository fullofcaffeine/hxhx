/**
	Metadata named like a keyword stays metadata on a class.

	Why
	- Upstream std `cs/internal/Function.hx` and `java/internal/Function.hx`
	  declare `@:keep @:abstract @:nativeGen @:native(...) class Function`. The
	  helper-abstract scanner read the metadata name `abstract` as the keyword
	  and added a bogus abstract named after the next identifier (`nativeGen`),
	  with no underlying type and the class body as its members
	  (haxe_ocaml-ey6o2).

	What
	- `@:abstract class` and `@:final class` parse as the
	  one authored class, with its metadata, and no abstract.
	- Real abstracts and legacy `@:enum abstract` keep their abstract reading.
**/
class M14AbstractMetadataClassParseTest {
	static function classes(source:String):Array<String> {
		final declaration = ParserStage.parse(source, "Probe.hx").getDecl();
		return [
			for (c in HxModuleDecl.getClasses(declaration))
				HxClassDecl.getName(c) + (HxClassDecl.getMetadata(c).indexOf("__hxhx_abstract") >= 0 ? ":abstract" : ":class")
		];
	}

	static function expect(source:String, expected:Array<String>):Void {
		final actual = classes(source);
		if (actual.join(" ") != expected.join(" "))
			throw "parsed " + source + "\n  expected " + expected.join(" ") + "\n  got      " + actual.join(" ");
	}

	static function main():Void {
		expect('@:keep @:abstract @:nativeGen @:native("haxe.lang.Function") class Function {\n\tfunction new(arity:Int, type:Int) {}\n}', ["Function:class"]);
		expect('@:abstract class Base {}', ["Base:class"]);
		expect('@:final class Sealed {}', ["Sealed:class"]);
		expect('abstract Real(Int) {\n\tpublic function new() this = 1;\n}', ["Real:abstract"]);
		expect('@:enum abstract Legacy(Int) {\n\tvar One = 1;\n}', ["Legacy:abstract"]);
		expect('@:forward abstract Wrapped(Array<Int>) {}', ["Wrapped:abstract"]);
		Sys.println("ABSTRACT_METADATA_CLASS_PARSE:PASS");
	}
}
