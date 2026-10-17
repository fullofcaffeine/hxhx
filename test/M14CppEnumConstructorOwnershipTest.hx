import backend.cpp.CppManagedEnumConstructor;
import backend.cpp.CppManagedEnumDescriptors;
import backend.cpp.CppTypedProgramProjection;

/** Enum construction must use the current declaration and occurrence of its owning program. */
class M14CppEnumConstructorOwnershipTest {
	static function program(bare:Bool = false):CppTypedProgramProjection {
		final source = bare ? 'class Main { static function main():Void { final item:Sample = Item(7); } } enum Sample { Item(value:Int); }' : 'class Main { static function main():Void { final item:Sample<Int> = Sample.Item(7); } } enum Sample<T> { Item(value:T); }';
		final parsed = new ResolvedModule("Main", "Main.hx", ParserStage.parse(source, "Main.hx"));
		return new CppTypedProgramProjection(new MacroExpandedProgram([TyperStage.typeResolvedModule(parsed, TyperIndex.build([parsed]))], false));
	}

	static function rejects(action:Void->Void, expected:String):Void {
		try
			action()
		catch (error:haxe.Exception) {
			if (error.message.indexOf(expected) < 0)
				throw error;
			return;
		}
		throw "enum construction accepted invalid evidence: " + expected;
	}

	static function main():Void {
		for (bare in [false, true])
			exercise(bare);
		Sys.println("CPP_ENUM_CONSTRUCTOR_OWNERSHIP:PASS");
	}

	/** Bare and qualified constructors retain callable facts before native projection. */
	static function exercise(bare:Bool):Void {
		final owner = program(bare);
		final enums = new CppManagedEnumDescriptors(owner);
		final fn = owner.requireClass(owner.requireClassIdentity("Main")).getFunctions()[0];
		var selected:Null<HxExpr> = null;
		for (statement in fn.getBody())
			TypedBackendSourceWalk.statement(statement, expression -> {
				if (TypedExactEnumConstructorSource.decode(expression) != null)
					selected = expression;
			}, _ -> {});
		if (selected == null)
			throw "enum fixture lost its constructor call";
		final catalog = fn.requireCaptureCatalog();
		final source = catalog.findCallableExpression(selected);
		final plan = new CppManagedEnumConstructor(selected, source, enums, type -> type, null);
		if (plan.resultType.getSemanticKey() != (bare ? "nominal:Main.Sample" : "nominal:Main.Sample<primitive:Int>"))
			throw "enum constructor lost its applied result type";
		final exact = TypedExactEnumConstructorSource.decode(selected);
		final copy = TypedExactEnumConstructorSource.encode(exact.owner, exact.modulePath, exact.declaration, exact.constructor, exact.callee, exact.arguments);
		if (catalog.findCallableExpression(copy) != null)
			throw "copied enum marker borrowed typed evidence";
		rejects(() -> new CppManagedEnumConstructor(copy, catalog.findCallableExpression(copy), enums, type -> type, null), "exact typed call");
		rejects(() -> new CppManagedEnumConstructor(selected, source, new CppManagedEnumDescriptors(program(bare)), type -> type, null),
			"another typed program");
		final forged = TypedExactEnumConstructorSource.encode(exact.owner, exact.modulePath, exact.declaration, "Other", exact.callee, exact.arguments);
		rejects(() -> new CppManagedEnumConstructor(forged, source, enums, type -> type, null), "exact typed call");
		final body = fn.getBody();
		body.push(HxStmt.SReturn(HxExpr.EInt(99), HxPos.unknown()));
		rejects(() -> catalog.findCallableExpression(selected), "projection");
		body.pop();
		if (catalog.findCallableExpression(selected) != source)
			throw "restored enum occurrence lost its typed owner";
	}
}
