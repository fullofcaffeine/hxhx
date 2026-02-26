#if macro
using haxe.macro.Tools;

import haxe.macro.Compiler;
import haxe.macro.Context;
import haxe.macro.Expr;
import haxe.macro.PlatformConfig;
import haxe.macro.PositionTools;
import haxe.macro.Printer;
import haxe.macro.Type;
import haxe.macro.TypeTools;
import haxe.macro.TypedExprTools;

class MacroBucket02Probe {
	static inline final PREFIX = "HX_MACRO_BUCKET02_";

	static function mark(moduleKey:String):Void {
		Compiler.define(PREFIX + moduleKey, "1");
	}

	static function probePlatformConfig():Void {
		final compilerConfig = Compiler.getConfiguration();
		if (compilerConfig == null) {
			Context.fatalError("haxe_macro_bucket02_basic: missing compiler configuration", Context.currentPos());
		}
		final platformConfig:PlatformConfig = compilerConfig.platformConfig;
		final supportsUnicode = platformConfig.supportsUnicode;
		if (supportsUnicode == null) {
			Context.fatalError("haxe_macro_bucket02_basic: invalid platformConfig.supportsUnicode", Context.currentPos());
		}
		mark("HAXE_MACRO_PLATFORMCONFIG");
	}

	static function probePositionTools():Void {
		final currentPos = Context.currentPos();
		final info = PositionTools.getInfos(currentPos);
		if (info.file == null || info.file.length == 0) {
			Context.fatalError("haxe_macro_bucket02_basic: PositionTools.getInfos produced empty file", Context.currentPos());
		}
		final rebuilt = PositionTools.make(info);
		if (rebuilt == null) {
			Context.fatalError("haxe_macro_bucket02_basic: PositionTools.make returned null", Context.currentPos());
		}
		mark("HAXE_MACRO_POSITIONTOOLS");
	}

	static function probePrinter():Void {
		final printer = new Printer("  ");
		final printedExpr = printer.printExpr(macro 1 + 2);
		if (printedExpr.indexOf("+") == -1) {
			Context.fatalError("haxe_macro_bucket02_basic: Printer.printExpr regression", Context.currentPos());
		}
		mark("HAXE_MACRO_PRINTER");
	}

	static function probeToolsAndTypeModules():Void {
		final extensionExpr = (macro 3 + 4).toString();
		if (extensionExpr.length == 0) {
			Context.fatalError("haxe_macro_bucket02_basic: Tools extension dispatch regression", Context.currentPos());
		}
		mark("HAXE_MACRO_TOOLS");

		final stringType:Type = Context.typeof(macro "portable");
		switch (stringType) {
			case TInst(classRef, _):
				final classType = classRef.get();
				if (classType.name != "String") {
					Context.fatalError("haxe_macro_bucket02_basic: expected String type", Context.currentPos());
				}
			case _:
				Context.fatalError("haxe_macro_bucket02_basic: unexpected type shape", Context.currentPos());
		}
		mark("HAXE_MACRO_TYPE");

		final typeString = TypeTools.toString(stringType);
		if (typeString.indexOf("String") == -1) {
			Context.fatalError("haxe_macro_bucket02_basic: TypeTools.toString regression", Context.currentPos());
		}
		mark("HAXE_MACRO_TYPETOOLS");

		final typedExpr = Context.typeExpr(macro 1 + 2);
		var visitedNodes = 0;
		TypedExprTools.iter(typedExpr, function(_:haxe.macro.Type.TypedExpr):Void {
			visitedNodes++;
		});
		if (visitedNodes <= 0) {
			Context.fatalError("haxe_macro_bucket02_basic: TypedExprTools.iter did not visit nodes", Context.currentPos());
		}
		final typedExprString = TypedExprTools.toString(typedExpr, false);
		if (typedExprString.length == 0) {
			Context.fatalError("haxe_macro_bucket02_basic: TypedExprTools.toString regression", Context.currentPos());
		}
		mark("HAXE_MACRO_TYPEDEXPRTOOLS");
	}

	public static function run():Void {
		probePlatformConfig();
		probePositionTools();
		probePrinter();
		probeToolsAndTypeModules();
		Compiler.define("HX_MACRO_BUCKET02_DONE", "1");
	}
}
#end

class Main {
	static function printModuleStatus(moduleName:String, enabled:Bool):Void {
		final status = enabled ? "ok" : "missing";
		Sys.println(moduleName + "=" + status);
	}

	static function main() {
		#if HX_MACRO_BUCKET02_HAXE_MACRO_PLATFORMCONFIG
		printModuleStatus("haxe.macro.PlatformConfig", true);
		#else
		printModuleStatus("haxe.macro.PlatformConfig", false);
		#end

		#if HX_MACRO_BUCKET02_HAXE_MACRO_POSITIONTOOLS
		printModuleStatus("haxe.macro.PositionTools", true);
		#else
		printModuleStatus("haxe.macro.PositionTools", false);
		#end

		#if HX_MACRO_BUCKET02_HAXE_MACRO_PRINTER
		printModuleStatus("haxe.macro.Printer", true);
		#else
		printModuleStatus("haxe.macro.Printer", false);
		#end

		#if HX_MACRO_BUCKET02_HAXE_MACRO_TOOLS
		printModuleStatus("haxe.macro.Tools", true);
		#else
		printModuleStatus("haxe.macro.Tools", false);
		#end

		#if HX_MACRO_BUCKET02_HAXE_MACRO_TYPE
		printModuleStatus("haxe.macro.Type", true);
		#else
		printModuleStatus("haxe.macro.Type", false);
		#end

		#if HX_MACRO_BUCKET02_HAXE_MACRO_TYPETOOLS
		printModuleStatus("haxe.macro.TypeTools", true);
		#else
		printModuleStatus("haxe.macro.TypeTools", false);
		#end

		#if HX_MACRO_BUCKET02_HAXE_MACRO_TYPEDEXPRTOOLS
		printModuleStatus("haxe.macro.TypedExprTools", true);
		#else
		printModuleStatus("haxe.macro.TypedExprTools", false);
		#end

		#if HX_MACRO_BUCKET02_DONE
		Sys.println("macro.bucket02=done");
		#else
		Sys.println("macro.bucket02=missing");
		#end
	}
}
