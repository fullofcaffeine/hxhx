#if macro
import haxe.macro.Compiler;
import haxe.macro.Context;

class XmlBucket01MacroProbe {
	static inline final PREFIX = "HX_XML_BUCKET01_";
	static final MODULES:Array<String> = [
		"haxe.xml.Access",
		"haxe.xml.Check",
		"haxe.xml.Fast",
		"haxe.xml.Parser",
		"haxe.xml.Printer"
	];

	static function defineKey(moduleName:String):String {
		return PREFIX + moduleName.toUpperCase().split(".").join("_");
	}

	public static function run():Void {
		for (moduleName in MODULES) {
			final moduleTypes = Context.getModule(moduleName);
			if (moduleTypes == null || moduleTypes.length == 0) {
				Context.fatalError("haxe_xml_bucket01_basic: missing module " + moduleName, Context.currentPos());
			}
			Compiler.define(defineKey(moduleName), "1");
		}
		Compiler.define("HX_XML_BUCKET01_DONE", "1");
	}
}
#end

class Main {
	static function printStatus(name:String, ok:Bool):Void {
		Sys.println(name + "=" + (ok ? "ok" : "missing"));
	}

	static function main() {
		#if HX_XML_BUCKET01_HAXE_XML_ACCESS
		printStatus("haxe.xml.Access", true);
		#else
		printStatus("haxe.xml.Access", false);
		#end

		#if HX_XML_BUCKET01_HAXE_XML_CHECK
		printStatus("haxe.xml.Check", true);
		#else
		printStatus("haxe.xml.Check", false);
		#end

		#if HX_XML_BUCKET01_HAXE_XML_FAST
		printStatus("haxe.xml.Fast", true);
		#else
		printStatus("haxe.xml.Fast", false);
		#end

		#if HX_XML_BUCKET01_HAXE_XML_PARSER
		printStatus("haxe.xml.Parser", true);
		#else
		printStatus("haxe.xml.Parser", false);
		#end

		#if HX_XML_BUCKET01_HAXE_XML_PRINTER
		printStatus("haxe.xml.Printer", true);
		#else
		printStatus("haxe.xml.Printer", false);
		#end

		#if HX_XML_BUCKET01_DONE
		Sys.println("haxe.xml.bucket01=done");
		#else
		Sys.println("haxe.xml.bucket01=missing");
		#end
	}
}
