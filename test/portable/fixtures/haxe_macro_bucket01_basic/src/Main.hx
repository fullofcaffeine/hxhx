#if macro
import haxe.macro.CompilationServer;
import haxe.macro.Compiler;
import haxe.macro.ComplexTypeTools;
import haxe.macro.Context;
import haxe.macro.DisplayMode;
import haxe.macro.ExampleJSGenerator;
import haxe.macro.Expr;
import haxe.macro.ExprTools;
import haxe.macro.Format;
import haxe.macro.JSGenApi;
import haxe.macro.MacroStringTools;

class MacroBucket01Probe {
	static inline final PREFIX = "HX_MACRO_BUCKET01_";

	static function mark(moduleKey:String):Void {
		Compiler.define(PREFIX + moduleKey, "1");
	}

	static function probeCompilationServer():Void {
		CompilationServer.invalidateFiles([]);
		mark("HAXE_MACRO_COMPILATIONSERVER");
	}

	static function probeCompiler():Void {
		final compilerConfig = Compiler.getConfiguration();
		if (compilerConfig == null) {
			Context.fatalError("haxe_macro_bucket01_basic: expected compiler configuration", Context.currentPos());
		}
		mark("HAXE_MACRO_COMPILER");
	}

	static function probeComplexTypeTools():Void {
		final complexTypeString = ComplexTypeTools.toString(macro :Int);
		if (complexTypeString != "Int") {
			Context.fatalError("haxe_macro_bucket01_basic: ComplexTypeTools.toString regression", Context.currentPos());
		}
		mark("HAXE_MACRO_COMPLEXTYPETOOLS");
	}

	static function probeContextAndDisplayMode():Void {
		final displayMode:DisplayMode = Context.getDisplayMode();
		switch (displayMode) {
			case None | Default | Definition | TypeDefinition | Implementation | Package | Hover | ModuleSymbols | Signature:
			case References(_, _):
			case WorkspaceSymbols(_):
		}
		mark("HAXE_MACRO_CONTEXT");
		mark("HAXE_MACRO_DISPLAYMODE");
	}

	static function probeExprModules():Void {
		final expr:Expr = macro 1 + 2;
		final exprText = ExprTools.toString(expr);
		if (exprText.length == 0) {
			Context.fatalError("haxe_macro_bucket01_basic: ExprTools.toString returned empty output", Context.currentPos());
		}

		final formattedExpr = Format.format(macro "hello");
		if (formattedExpr == null) {
			Context.fatalError("haxe_macro_bucket01_basic: Format.format returned null", Context.currentPos());
		}

		mark("HAXE_MACRO_EXPR");
		mark("HAXE_MACRO_EXPRTOOLS");
		mark("HAXE_MACRO_FORMAT");
	}

	static function probeMacroStringTools():Void {
		final dotPath = MacroStringTools.toDotPath(["haxe", "macro"], "Expr");
		if (dotPath != "haxe.macro.Expr") {
			Context.fatalError("haxe_macro_bucket01_basic: MacroStringTools.toDotPath regression", Context.currentPos());
		}
		mark("HAXE_MACRO_MACROSTRINGTOOLS");
	}

	static function probeExampleJsAndJsGenApi():Void {
		final jsGenApi:Null<JSGenApi> = null;
		if (jsGenApi != null) {
			Context.fatalError("haxe_macro_bucket01_basic: JSGenApi probe invariant violated", Context.currentPos());
		}

		ExampleJSGenerator.use();
		mark("HAXE_MACRO_JSGENAPI");
		mark("HAXE_MACRO_EXAMPLEJSGENERATOR");
	}

	static function probeMacroType():Void {
		final macroTypeComplex = macro :haxe.macro.MacroType<[haxe.macro.MacroStringTools.toComplex("Int")]>;
		Context.resolveType(macroTypeComplex, Context.currentPos());
		mark("HAXE_MACRO_MACROTYPE");
	}

	public static function run():Void {
		probeCompilationServer();
		probeCompiler();
		probeComplexTypeTools();
		probeContextAndDisplayMode();
		probeExprModules();
		probeMacroStringTools();
		probeExampleJsAndJsGenApi();
		probeMacroType();
		Compiler.define("HX_MACRO_BUCKET01_DONE", "1");
	}
}
#end

class Main {
	static function printModuleStatus(moduleName:String, enabled:Bool):Void {
		final status = enabled ? "ok" : "missing";
		Sys.println(moduleName + "=" + status);
	}

	static function main() {
		#if HX_MACRO_BUCKET01_HAXE_MACRO_COMPILATIONSERVER
		printModuleStatus("haxe.macro.CompilationServer", true);
		#else
		printModuleStatus("haxe.macro.CompilationServer", false);
		#end

		#if HX_MACRO_BUCKET01_HAXE_MACRO_COMPILER
		printModuleStatus("haxe.macro.Compiler", true);
		#else
		printModuleStatus("haxe.macro.Compiler", false);
		#end

		#if HX_MACRO_BUCKET01_HAXE_MACRO_COMPLEXTYPETOOLS
		printModuleStatus("haxe.macro.ComplexTypeTools", true);
		#else
		printModuleStatus("haxe.macro.ComplexTypeTools", false);
		#end

		#if HX_MACRO_BUCKET01_HAXE_MACRO_CONTEXT
		printModuleStatus("haxe.macro.Context", true);
		#else
		printModuleStatus("haxe.macro.Context", false);
		#end

		#if HX_MACRO_BUCKET01_HAXE_MACRO_DISPLAYMODE
		printModuleStatus("haxe.macro.DisplayMode", true);
		#else
		printModuleStatus("haxe.macro.DisplayMode", false);
		#end

		#if HX_MACRO_BUCKET01_HAXE_MACRO_EXAMPLEJSGENERATOR
		printModuleStatus("haxe.macro.ExampleJSGenerator", true);
		#else
		printModuleStatus("haxe.macro.ExampleJSGenerator", false);
		#end

		#if HX_MACRO_BUCKET01_HAXE_MACRO_EXPR
		printModuleStatus("haxe.macro.Expr", true);
		#else
		printModuleStatus("haxe.macro.Expr", false);
		#end

		#if HX_MACRO_BUCKET01_HAXE_MACRO_EXPRTOOLS
		printModuleStatus("haxe.macro.ExprTools", true);
		#else
		printModuleStatus("haxe.macro.ExprTools", false);
		#end

		#if HX_MACRO_BUCKET01_HAXE_MACRO_FORMAT
		printModuleStatus("haxe.macro.Format", true);
		#else
		printModuleStatus("haxe.macro.Format", false);
		#end

		#if HX_MACRO_BUCKET01_HAXE_MACRO_JSGENAPI
		printModuleStatus("haxe.macro.JSGenApi", true);
		#else
		printModuleStatus("haxe.macro.JSGenApi", false);
		#end

		#if HX_MACRO_BUCKET01_HAXE_MACRO_MACROSTRINGTOOLS
		printModuleStatus("haxe.macro.MacroStringTools", true);
		#else
		printModuleStatus("haxe.macro.MacroStringTools", false);
		#end

		#if HX_MACRO_BUCKET01_HAXE_MACRO_MACROTYPE
		printModuleStatus("haxe.macro.MacroType", true);
		#else
		printModuleStatus("haxe.macro.MacroType", false);
		#end

		#if HX_MACRO_BUCKET01_DONE
		Sys.println("macro.bucket01=done");
		#else
		Sys.println("macro.bucket01=missing");
		#end
	}
}
