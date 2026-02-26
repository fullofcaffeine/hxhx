#if macro
import haxe.macro.Compiler;
import haxe.macro.Context;

class ZipBucket01MacroProbe {
	static inline final PREFIX = "HX_ZIP_BUCKET01_";
	static final MODULES:Array<String> = [
		"haxe.zip.Compress",
		"haxe.zip.Entry",
		"haxe.zip.FlushMode",
		"haxe.zip.Huffman",
		"haxe.zip.InflateImpl",
		"haxe.zip.Reader",
		"haxe.zip.Tools",
		"haxe.zip.Uncompress",
		"haxe.zip.Writer"
	];

	static function defineKey(moduleName:String):String {
		return PREFIX + moduleName.toUpperCase().split(".").join("_");
	}

	public static function run():Void {
		for (moduleName in MODULES) {
			final moduleTypes = Context.getModule(moduleName);
			if (moduleTypes == null || moduleTypes.length == 0) {
				Context.fatalError("haxe_zip_bucket01_basic: missing module " + moduleName, Context.currentPos());
			}
			Compiler.define(defineKey(moduleName), "1");
		}
		Compiler.define("HX_ZIP_BUCKET01_DONE", "1");
	}
}
#end

class Main {
	static function printStatus(name:String, ok:Bool):Void {
		Sys.println(name + "=" + (ok ? "ok" : "missing"));
	}

	static function main() {
		#if HX_ZIP_BUCKET01_HAXE_ZIP_COMPRESS
		printStatus("haxe.zip.Compress", true);
		#else
		printStatus("haxe.zip.Compress", false);
		#end

		#if HX_ZIP_BUCKET01_HAXE_ZIP_ENTRY
		printStatus("haxe.zip.Entry", true);
		#else
		printStatus("haxe.zip.Entry", false);
		#end

		#if HX_ZIP_BUCKET01_HAXE_ZIP_FLUSHMODE
		printStatus("haxe.zip.FlushMode", true);
		#else
		printStatus("haxe.zip.FlushMode", false);
		#end

		#if HX_ZIP_BUCKET01_HAXE_ZIP_HUFFMAN
		printStatus("haxe.zip.Huffman", true);
		#else
		printStatus("haxe.zip.Huffman", false);
		#end

		#if HX_ZIP_BUCKET01_HAXE_ZIP_INFLATEIMPL
		printStatus("haxe.zip.InflateImpl", true);
		#else
		printStatus("haxe.zip.InflateImpl", false);
		#end

		#if HX_ZIP_BUCKET01_HAXE_ZIP_READER
		printStatus("haxe.zip.Reader", true);
		#else
		printStatus("haxe.zip.Reader", false);
		#end

		#if HX_ZIP_BUCKET01_HAXE_ZIP_TOOLS
		printStatus("haxe.zip.Tools", true);
		#else
		printStatus("haxe.zip.Tools", false);
		#end

		#if HX_ZIP_BUCKET01_HAXE_ZIP_UNCOMPRESS
		printStatus("haxe.zip.Uncompress", true);
		#else
		printStatus("haxe.zip.Uncompress", false);
		#end

		#if HX_ZIP_BUCKET01_HAXE_ZIP_WRITER
		printStatus("haxe.zip.Writer", true);
		#else
		printStatus("haxe.zip.Writer", false);
		#end

		#if HX_ZIP_BUCKET01_DONE
		Sys.println("haxe.zip.bucket01=done");
		#else
		Sys.println("haxe.zip.bucket01=missing");
		#end
	}
}
