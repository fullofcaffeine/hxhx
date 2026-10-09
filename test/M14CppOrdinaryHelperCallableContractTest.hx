import backend.cpp.CppTargetCore;
import backend.cpp.CppTypedProgramProjection;

/** Helper bodies must use the templates and exact parameter names selected for their declarations. */
class M14CppOrdinaryHelperCallableContractTest {
	public static function run():Void {
		final failures = new Array<String>();
		for (source in [
			'class TypeTools { public static function findField<A>(int:A, int_:String):A return int; }',
			'class TypeTools { public static function map(int:Int, int_:Int):Int return int; }',
			'class MacroStringTools { public static function isFormatExpr(int:String, int_:String):Bool return false; }',
			'class SysTools { public static function quoteUnixArg<A>(int:String, int_:A):String return int; }',
			'class SysTools { public static function quoteWinArg(int:String, int_:Bool = false):String return int; }'
		]) {
			final module = new ResolvedModule("Probe", "Probe.hx", ParserStage.parse(source, "Probe.hx"));
			final typed = TyperStage.typeResolvedModule(module, TyperIndex.build([module]));
			final program = new CppTypedProgramProjection(new MacroExpandedProgram([typed], false));
			final lookup = @:privateAccess CppTargetCore.collectClassLookup(program);
			final owner = program.getModules()[0].projection.getClasses()[0];
			final fn = owner.getFunctions()[0].getDeclaration();
			final contract = @:privateAccess CppTargetCore.emittedCallableContract(fn, owner.getDeclaration(), lookup);
			final rendered = @:privateAccess CppTargetCore.renderHelperMethod(fn, owner.getDeclaration(), lookup).join("\n");
			final method = HxFunctionDecl.getName(fn);
			if ((method == "findField" || method == "quoteUnixArg")
				&& (contract.getTemplates().length != 1 || rendered.indexOf("template<typename A>") < 0))
				failures.push(method + " must emit its selected source generic");
			if (rendered.indexOf("int__2") < 0 || rendered.indexOf(" int_") < 0)
				failures.push(method + " must keep distinct planned parameter names");
			if (method == "quoteUnixArg") {
				if (rendered.indexOf("__hxhx_quote_unix_arg(int__2)") < 0 || rendered.indexOf("__hxhx_quote_unix_arg(int_)") >= 0)
					failures.push("quoteUnixArg must quote the first exact source parameter");
			} else if (method == "quoteWinArg") {
				if (rendered.indexOf("__hxhx_quote_win_arg(int__2, int_)") < 0)
					failures.push("quoteWinArg must keep the value and policy parameters distinct");
			} else if (method == "map") {
				if (rendered.indexOf("return int__2;") < 0 || rendered.indexOf("return int_;") >= 0)
					failures.push("map must return the first exact source parameter");
			} else if (rendered.indexOf("(void)int__2;") < 0 || rendered.indexOf("(void)int_;") < 0) {
				failures.push(method + " must reference each exact parameter in its body");
			}
		}
		if (failures.length > 0)
			throw failures.join("\n");
		Sys.println("CPP_ORDINARY_HELPER_CALLABLE_CONTRACT:PASS");
	}

	static function main():Void
		run();
}
