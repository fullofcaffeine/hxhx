#if macro
import haxe.macro.Compiler;
import haxe.macro.Context;

class RttiBucket01MacroProbe {
	static inline final PREFIX = "HX_RTTI_BUCKET01_";
	static final MODULES:Array<String> = ["haxe.rtti.CType", "haxe.rtti.Meta", "haxe.rtti.Rtti", "haxe.rtti.XmlParser"];

	static function defineKey(moduleName:String):String {
		return PREFIX + moduleName.toUpperCase().split(".").join("_");
	}

	public static function run():Void {
		for (moduleName in MODULES) {
			final moduleTypes = Context.getModule(moduleName);
			if (moduleTypes == null || moduleTypes.length == 0) {
				Context.fatalError("haxe_rtti_bucket01_basic: missing module " + moduleName, Context.currentPos());
			}
			Compiler.define(defineKey(moduleName), "1");
		}
		Compiler.define("HX_RTTI_BUCKET01_DONE", "1");
	}
}
#end

class Main {
	static function printStatus(name:String, enabled:Bool):Void {
		Sys.println(name + "=" + (enabled ? "ok" : "missing"));
	}

	static function main() {
		#if HX_RTTI_BUCKET01_HAXE_RTTI_CTYPE
		printStatus("haxe.rtti.CType", true);
		#else
		printStatus("haxe.rtti.CType", false);
		#end

		#if HX_RTTI_BUCKET01_HAXE_RTTI_META
		printStatus("haxe.rtti.Meta", true);
		#else
		printStatus("haxe.rtti.Meta", false);
		#end

		#if HX_RTTI_BUCKET01_HAXE_RTTI_RTTI
		printStatus("haxe.rtti.Rtti", true);
		#else
		printStatus("haxe.rtti.Rtti", false);
		#end

		#if HX_RTTI_BUCKET01_HAXE_RTTI_XMLPARSER
		printStatus("haxe.rtti.XmlParser", true);
		#else
		printStatus("haxe.rtti.XmlParser", false);
		#end

		#if HX_RTTI_BUCKET01_DONE
		Sys.println("haxe.rtti.bucket01=done");
		#else
		Sys.println("haxe.rtti.bucket01=missing");
		#end
	}
}
