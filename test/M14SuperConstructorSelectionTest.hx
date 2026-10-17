import backend.cpp.CppTypedProgramProjection;

/** Parent calls preserve exact declaration, applied parameter types, and non-allocating source shape. */
class M14SuperConstructorSelectionTest {
	static function rejects(action:Void->Void, fragment:String):Void {
		try {
			action();
		} catch (failure:haxe.Exception) {
			if (failure.message.indexOf(fragment) >= 0)
				return;
			throw failure;
		}
		throw "invalid parent constructor fact was accepted";
	}

	static function main():Void {
		final source = "class Main { static function main() { new Child(7); } } "
			+ "class Base<T> { public var value:T; public function new(value:T) { this.value = value; } } "
			+ "class Child extends Base<Int> { public function new(value:Int) { super(value); } } "
			+ "class Wrong extends Base<Int> { public function new() { super(\"wrong\"); } }";
		final module = new ResolvedModule("Main", "Main.hx", ParserStage.parse(source, "Main.hx"));
		final typed = TyperStage.typeResolvedModule(module, TyperIndex.build([module]));
		final program = new CppTypedProgramProjection(new MacroExpandedProgram([typed], false));
		final owner = program.requireClass(program.requireClassIdentity("Main.Child"));
		final constructor = owner.getFunctions()[0];
		final entries = constructor.getConstructorCatalog().getEntries();
		if (entries.length != 1 || !entries[0].getIsSuperCall())
			throw "parent call was lost or treated as allocation";
		final entry = entries[0];
		final application = entry.requireApplication();
		if (application.getDeclaration().getOwner().getCanonicalName() != "Main.Base"
			|| application.getParameterTypes()[0].getSemanticKey() != "primitive:Int"
			|| entry.getConstructedType().getTypeArguments()[0].getSemanticKey() != "primitive:Int")
			throw "parent call lost its exact applied constructor";
		final base = program.requireClass(program.requireClassIdentity("Main.Base")).getFunctions()[0];
		if (base.requireSemanticDeclaration() != application.getDeclaration()
			|| base.getParameters()[0].getBinding().getType().getTypeParameterIdentity() == null)
			throw "parent selection replaced the declaration or mutated its generic binder";
		rejects(() -> base.requireConstructor(entry.getExpression()), "absent from the current function");
		final allocation = program.requireClass(program.requireClassIdentity("Main")).getFunctions()[0].getConstructorCatalog().getEntries()[0];
		if (allocation.getIsSuperCall())
			throw "ordinary allocation became parent initialization";
		final wrong = program.requireClass(program.requireClassIdentity("Main.Wrong")).getFunctions()[0].getConstructorCatalog().getEntries()[0];
		rejects(() -> wrong.requireApplication(), "unresolved constructor");
		switch entry.getExpression() {
			case ECall(ESuper, arguments):
				arguments[0] = EInt(9);
			case _:
				throw "parent call changed its source shape";
		}
		rejects(() -> entry.assertCurrent(), "arguments were replaced");
		Sys.println("SUPER_CONSTRUCTOR_SELECTION:PASS");
	}
}
