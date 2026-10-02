import backend.cpp.CppMacroExpr;
import backend.cpp.CppTargetCore;
import backend.js.JsExprEmitter;
import backend.source.SourceTargetCommon;
import backend.vm.NekoMacroExprLowering;
import hxhxmacrohost.api.RuntimeMacroExprs;

/** The public runtime parser and each quote adapter retain nested expression grouping. */
class M14SourceParenthesizedMacroTest {
	static function main():Void {
		final sources = ["((value))", "(value = 3)", "((value = 3))", "(1 + 2) * 3", "(value) = 4"];
		final expected = sys.io.File.getContent("test/oracle/source_parenthesized_seed/syntax.stdout");
		final actual = [
			for (source in sources)
				@:privateAccess M14SourceParenthesizedSyntaxTest.shape(RuntimeMacroExprs.parse(source, null))
		].join("\n") + "\n";
		if (actual != expected)
			throw "public runtime macro parser changed parentheses: " + actual;
		final parsed = HxParser.parseCompleteExprText("((value = 3))");
		final outputs = [
			CppMacroExpr.macroExpr(parsed, []), @:privateAccess
			CppTargetCore.macroExprText(parsed, []),
			JsExprEmitter.emit(EMacroExpr(parsed, []), null),
			NekoMacroExprLowering.render(parsed, [], _ -> "unused"), @:privateAccess
			SourceTargetCommon.pythonMacroExpr(parsed, []), @:privateAccess
			SourceTargetCommon.phpMacroExpr(parsed, [])
		];
		for (index in 0...outputs.length)
			if (outputs[index].split("EParenthesis").length != 3 || outputs[index].indexOf("__hxhx_parenthesized") >= 0)
				throw "quote adapter changed nested parentheses: " + index + ": " + outputs[index];
		Sys.println("SOURCE_PARENTHESIZED_MACRO:PASS");
	}
}
