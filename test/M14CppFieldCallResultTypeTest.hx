import HxExpr;
import haxe.ds.StringMap;
import backend.cpp.CppTargetCore;

/** Observe ordinary field-call result types from independent Haxe signatures. */
class M14CppFieldCallResultTypeTest {
	static function main():Void {
		final parsed = ParserStage.parse('class Owner {} class Service { public static function count():Int return 7; public function label():String return "value"; public function ready():Bool return true; }',
			"Owner.hx");
		final classes = HxModuleDecl.getClasses(parsed.getDecl());
		final names = new StringMap<Bool>();
		final byName = new StringMap<HxClassDecl>();
		for (owner in classes) {
			names.set(HxClassDecl.getName(owner), true);
			byName.set(HxClassDecl.getName(owner), owner);
		}
		final scope = @:privateAccess CppTargetCore.renderScope(classes[0], {names: names, byName: byName, all: classes}, "void");
		scope.localTypes.set("service", "std::shared_ptr<Service>");
		final cases = [
			{receiver: "Service", method: "count", expected: "int"},
			{receiver: "service", method: "label", expected: "std::string"},
			{receiver: "service", method: "ready", expected: "bool"}
		];
		for (item in cases) {
			final expression = ECall(EField(EIdent(item.receiver), item.method), []);
			final explicit = @:privateAccess CppTargetCore.exprCppType(expression, scope);
			final inferred = @:privateAccess CppTargetCore.inferExprCppType(expression, scope);
			if (explicit != item.expected || inferred != item.expected)
				throw item.method + ": expected " + item.expected + ", got " + explicit + "/" + inferred;
			Sys.println(item.method + ":" + explicit + ":" + inferred);
		}
	}
}
