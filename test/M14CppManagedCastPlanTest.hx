import backend.cpp.CppManagedCastPlan;
import backend.cpp.CppTypedProgramProjection;

/** Exact program ownership and storage equality must precede any unchecked cast admission. */
class M14CppManagedCastPlanTest {
	static function project(source:String):CppTypedProgramProjection {
		final resolved = new ResolvedModule("Main", "Main.hx", ParserStage.parse(source, "Main.hx"));
		return new CppTypedProgramProjection(new MacroExpandedProgram([TyperStage.typeResolvedModule(resolved, TyperIndex.build([resolved]))], false));
	}

	static function authored(program:CppTypedProgramProjection):Array<TypedBackendCastOccurrence> {
		final result = new Array<TypedBackendCastOccurrence>();
		for (module in program.getModules())
			for (owner in module.projection.getClasses())
				for (initializer in owner.getFieldInitializers())
					TypedBackendSourceWalk.expression(initializer.getExpression(), expression -> {
						final occurrence = initializer.findCast(expression);
						if (occurrence != null && !occurrence.isRepresentationPreserving())
							result.push(occurrence);
					});
		return result;
	}

	static function rejected(action:Void->Void, message:String):Void {
		try
			action()
		catch (failure:haxe.Exception) {
			if (failure.message.indexOf(message) < 0)
				throw failure;
			return;
		}
		throw "invalid cast plan was admitted: " + message;
	}

	static function main():Void {
		final source = sys.io.File.getContent("test/fixtures/cpp_managed_authored_cast_seed/Main.hx");
		final program = project(source);
		final plan = new CppManagedCastPlan(program);
		final casts = authored(program);
		if (casts.length != 5)
			throw "missing authored field cast coverage";
		for (occurrence in casts) {
			plan.requireStoredValue(occurrence);
			if (plan.retainsNull(occurrence.getTargetType()))
				throw 'scalar abstract backing accepted null instead of requiring an explicit conversion';
		}
		final foreign = authored(project(source));
		for (occurrence in foreign)
			rejected(() -> plan.requireStoredValue(occurrence), "current initializer projection");
		for (declarations in [
			"static var value:Hidden<Bool> = cast 7;",
			"static var source:Carrier<Int>; static var value:Carrier<Bool> = cast source;",
			"static var value:Int = cast(7, Int);",
			"static var source:Dynamic = 7; static var value:Int = cast source;"
		]) {
			final invalid = project("class Main { " + declarations + " static function main():Void {} } abstract Hidden<T>(T) {} class Carrier<T> {}");
			final selected = authored(invalid);
			if (selected.length != 1)
				throw "negative fixture lost its cast";
			rejected(() -> new CppManagedCastPlan(invalid).requireStoredValue(selected[0]), "explicit runtime conversion plan");
		}
		Sys.println("CPP_MANAGED_CAST_PLAN:PASS");
	}
}
