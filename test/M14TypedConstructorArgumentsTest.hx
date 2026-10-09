import backend.cpp.CppManagedClassStorage;
import backend.cpp.CppTypedProgramProjection;

/** Constructor transport must distinguish omitted slots from authored nulls and preserve exact ownership. */
class M14TypedConstructorArgumentsTest {
	static function rejected(action:Void->Void, expected:String):Void {
		try
			action()
		catch (failure:haxe.Exception) {
			if (failure.message.indexOf(expected) < 0)
				throw failure;
			return;
		}
		throw "constructor argument check accepted " + expected;
	}

	static function main():Void {
		final source = 'class Main { static function main() { new Box<String>(); new Box<String>(null); new Box<String>("set"); new Box<String>("set", "!"); new Box<Int>(3); } static function inherited() { new Holder(new ArgChild()); } }'
			+ 'class Box<T> { public function new(?value:T, ?suffix:String) {} }'
			+ 'class ArgBase { public function new() {} } class ArgChild extends ArgBase { public function new() { super(); } }'
			+ 'class Holder { public function new(value:ArgBase) {} }'
			+ 'class Required { public function new(value:Int) {} }'
			+ 'class Child extends Box<String> { public function new() { super(); } }';
		final resolved = new ResolvedModule("Main", "Main.hx", ParserStage.parse(source, "Main.hx"));
		final typed = TyperStage.typeResolvedModule(resolved, TyperIndex.build([resolved]));
		final program = new CppTypedProgramProjection(new MacroExpandedProgram([typed], false));
		final main = program.requireClass(program.requireClassIdentity("Main")).getFunctions()[0];
		final entries = main.getConstructorCatalog().getEntries();
		final expected = [
			"Omitted,Omitted",
			"Supplied(0),Omitted",
			"Supplied(0),Omitted",
			"Supplied(0),Supplied(1)",
			"Supplied(0),Omitted"
		];
		if (entries.length != expected.length)
			throw "constructor fixture lost an occurrence";
		for (index in 0...entries.length) {
			final binding = entries[index].requireArgumentBinding();
			if ([for (slot in binding.getSlots()) Std.string(slot)].join(",") != expected[index])
				throw "constructor argument mapping differs at " + index;
			if (binding.getFunctionType().getFunctionParameters()[0].type.getSemanticKey() != (index == 4 ? "primitive:Int" : "primitive:String"))
				throw "constructor argument mapping lost generic substitution";
			final copy = binding.getSlots();
			copy.resize(0);
			if (binding.getSlots().length != 2)
				throw "caller mutated constructor argument slots";
		}
		if (entries[0].requireArgumentBinding().getSemanticKey() == entries[1].requireArgumentBinding().getSemanticKey())
			throw "omission and explicit null have the same argument identity";
		final inherited = program.requireClass(program.requireClassIdentity("Main")).getFunctions()[1].getConstructorCatalog().getEntries();
		for (entry in inherited)
			entry.requireArgumentBinding();
		rejected(() -> entries[2].requireApplication().requireArgumentBinding([TyType.fromHintText("Int")], [Value]), "stale operand type");
		final child = program.requireClass(program.requireClassIdentity("Main.Child")).getFunctions()[0];
		final parent = child.getConstructorCatalog().getEntries()[0];
		if (!parent.getIsSuperCall() || !parent.requireArgumentBinding().getSlots()[0].match(Omitted))
			throw "parent construction lost omitted argument selection";
		final storage = new CppManagedClassStorage(program);
		final other = new CppTypedProgramProjection(new MacroExpandedProgram([
			new TypedModule(typed.getParsed(), typed.getEnv(), typed.getTypedClasses(), typed.getRevision(), typed.getSourceOrigin(),
				typed.getConditionalCompilation(), typed.getGeneratedDeclarations())
		], false));
		final foreign = other.requireClass(other.requireClassIdentity("Main")).getFunctions()[0].getConstructorCatalog().getEntries()[0];
		rejected(() -> storage.constructorApplication(foreign), "another program or occurrence");
		rejected(() -> entries[0].assertOwner("foreign", "revision"), "another executable or revision");
		final signature = entries[3].requireApplication().getCallableSignature();
		final required = program.requireClass(program.requireClassIdentity("Main.Required")).getFunctions()[0].requireSemanticDeclaration();
		rejected(() -> TyCallArgumentBinding.require(TyCallableSignature.fromDeclaration(required), [], [], Unchecked), "Not enough arguments");
		rejected(() -> TyCallArgumentBinding.require(signature, [TyType.fromHintText("Int")], [Value], Unchecked), "should be String");
		rejected(() -> TyCallArgumentBinding.require(signature, [for (_ in 0...3) TyType.fromHintText("String")], [Value, Value, Value], Unchecked),
			"Too many arguments");
		rejected(() -> entries[3].requireArgumentBinding().assertCurrent(signature.getFunctionType(), [TyType.fromHintText("String")], [Value]),
			"stale signature or operand count");
		switch entries[3].getExpression() {
			case ENew(_, arguments):
				final original = arguments[0];
				arguments[0] = HxExpr.EString("replacement");
				rejected(() -> entries[3].requireArgumentBinding(), "arguments were replaced");
				arguments[0] = original;
			case _:
				throw "fixture lost construction expression";
		}
		Sys.println("TYPED_CONSTRUCTOR_ARGUMENTS:PASS");
	}
}
