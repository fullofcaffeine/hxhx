import backend.vm.NekoEnumConstructorPlan;
import backend.vm.NekoTypedProgramProjection;

/** Reserved constructor calls must agree with the program's exact enum declaration inventory. */
class M14NekoEnumConstructorPlanTest {
	static function rejects(fragment:String, action:Void->Void):Void {
		try
			action()
		catch (error:haxe.Exception) {
			if (error.message.indexOf(fragment) < 0)
				throw error;
			return;
		}
		throw "missing constructor rejection: " + fragment;
	}

	static function main():Void {
		final typed = @:privateAccess M14DeclaredFieldTypesTest.typeSources([
			{
				name: "Main",
				source: 'enum Item {Pair(number:Int,text:String);} enum Other {Pair(number:Int,text:String);} class Main {static function main():Void {var value=Item.Pair(1,"one");}}'
			}
		]);
		final module = typed[0].getBackendProjection();
		final program = new NekoTypedProgramProjection("enum-plan-fixture", [module]);
		var expression:Null<HxExpr> = null;
		for (owner in module.getClasses())
			for (fn in owner.getFunctions())
				for (statement in fn.getBody())
					TypedBackendSourceWalk.statement(statement, node -> {
						if (TypedExactEnumConstructorSource.decode(node) != null)
							expression = node;
					}, _ -> {});
		if (expression == null)
			throw "fixture lost exact constructor marker";
		final call = TypedExactEnumConstructorSource.decode(expression);
		final plan = NekoEnumConstructorPlan.fromExpression(program, expression);
		if (plan.selected.owner.requireSemanticFacts().getClassIdentity() != "Main.Item" || plan.getArguments().length != 2)
			throw "constructor selected another declaration";
		plan.getArguments().pop();
		if (plan.getArguments().length != 2)
			throw "constructor exposed its argument inventory";
		function marker(owner:String, module:String, declaration:String, name:String, args:Array<HxExpr>):HxExpr
			return TypedExactEnumConstructorSource.encode(owner, module, declaration, name, call.callee, args);
		rejects("does not belong",
			() -> NekoEnumConstructorPlan.fromExpression(program, marker("Main.Other", call.modulePath, call.declaration, call.constructor, call.arguments)));
		rejects("exact declaration",
			() -> NekoEnumConstructorPlan.fromExpression(program, marker(call.owner, "OtherModule", call.declaration, call.constructor, call.arguments)));
		rejects("exact declaration",
			() -> NekoEnumConstructorPlan.fromExpression(program, marker(call.owner, call.modulePath, call.declaration, "Other", call.arguments)));
		rejects("arity", () -> NekoEnumConstructorPlan.fromExpression(program, marker(call.owner, call.modulePath, call.declaration, call.constructor, [])));
		rejects("malformed", () -> NekoEnumConstructorPlan.fromExpression(program, ECall(EUnsupported(TypedExactEnumConstructorSource.marker()), [])));
		if (NekoEnumConstructorPlan.fromExpression(program, ECall(EIdent("ordinary"), [])) != null)
			throw "ordinary call gained enum identity";
		switch expression {
			case ECall(_, entries):
				switch entries[5] {
					case EArrayDecl(values): values.push(EInt(3));
					case _: throw "fixture lost argument payload";
				}
			case _:
				throw "fixture lost call";
		}
		rejects("changed after selection", () -> plan.getArguments());
		Sys.println("NEKO_ENUM_CONSTRUCTOR_PLAN:PASS");
	}
}
