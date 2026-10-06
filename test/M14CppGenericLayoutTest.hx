import backend.cpp.CppManagedClassStorage;
import backend.cpp.CppTypedProgramProjection;

/** Preserve applied field facts, declared generic defaults, and native allocation across multiple arguments. */
class M14CppGenericLayoutTest {
	static function rejects(action:Void->Void, fragment:String):Void {
		try {
			action();
		} catch (failure:haxe.Exception) {
			if (failure.message.indexOf(fragment) >= 0)
				return;
			throw failure;
		}
		throw "invalid generic layout was accepted";
	}

	static function main():Void {
		final root = "test/fixtures/cpp_generic_layout_seed";
		final path = root + "/Main.hx";
		final source = new ResolvedModule("Main", path, ParserStage.parse(sys.io.File.getContent(path), path));
		final typed = TyperStage.typeResolvedModule(source, TyperIndex.build([source]));
		final program = new CppTypedProgramProjection(new MacroExpandedProgram([typed], false));
		final storage = new CppManagedClassStorage(program);
		final types = new Array<TyType>();
		for (module in program.getModules())
			for (owner in module.projection.getClasses())
				for (fn in owner.getFunctions())
					for (entry in fn.getConstructorCatalog().getEntries())
						types.push(entry.getConstructedType());
		if (types.length != 3)
			throw "generic layout fixture lost its exact applications";
		final layouts = types.map(storage.requireType);
		final ints = layouts[0];
		final strings = layouts[1];
		final leaf = layouts[2];
		if (ints.type.getSemanticKey() == strings.type.getSemanticKey()
			|| ints.symbol != strings.symbol
			|| ints.fields[1].semanticType.getSemanticKey() != "primitive:Int"
			|| strings.fields[1].semanticType.getSemanticKey() != "primitive:String"
			|| leaf.fields[1].semanticType.getSemanticKey() != "primitive:String"
			|| !ints.declaredFields[1].semanticType.isTypeParameter())
			throw "applied layout conflated field types or public class identity";
		ints.fields.resize(0);
		ints.declaredFields.resize(0);
		if (storage.requireType(types[0]).fields.length != 2 || storage.requireType(types[0]).declaredFields.length != 2)
			throw "applied layout exposed its mutable field arrays";
		rejects(() -> storage.requireType(TyType.nominal(types[0].getNominalIdentity(), [])), "arity mismatch");
		// Cached applications must still reject a changed authored program.
		final body = HxFunctionDecl.getBody(typed.getTypedClasses()[0].getFunctions()[0].getSourceDeclaration());
		body.push(SExpr(EInt(99), HxPos.unknown()));
		rejects(() -> storage.requireType(types[0]), "typed body revision mismatch");
		body.pop();
		if (storage.requireType(types[0]).fields.length != 2)
			throw "restored source lost its applied layout";
		// @:generic requests distinct generated classes, outside ordinary erased identity.
		final specializedSource = new ResolvedModule("Specialized", "Specialized.hx",
			ParserStage.parse("@:generic class Specialized<T> { public function new() {} }", "Specialized.hx"));
		final specialized = new CppTypedProgramProjection(new MacroExpandedProgram([
			TyperStage.typeResolvedModule(specializedSource, TyperIndex.build([specializedSource]))
		], false));
		final specializedStorage = new CppManagedClassStorage(specialized);
		final specializedOwner = specialized.requireClass(specialized.requireClassIdentity("Specialized"))
			.getFunctions()[0].requireSemanticDeclaration().getOwner();
		rejects(() -> specializedStorage.requireType(TyType.nominal(specializedOwner, [types[0].getTypeArguments()[0]])),
			"specialized classes require their own runtime identity plan");
		M14CppManagedStartupExecutionTest.runFixture({
			sourceRoot: root,
			output: ".tmp/cpp-generic-layout",
			observer: "test/cpp_managed_heap/GenericLayoutObserver.cpp"
		});
		M14CppManagedStartupExecutionTest.runFixture({
			sourceRoot: "test/oracle/inherited_constructor_seed",
			output: ".tmp/cpp-inherited-generic-constructor",
			observer: "test/cpp_managed_heap/InstanceInitializerCaptureObserver.cpp"
		});
		Sys.println("CPP_GENERIC_LAYOUT:PASS");
	}
}
