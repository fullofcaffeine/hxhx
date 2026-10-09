import backend.cpp.CppTypedProgramProjection;

/** Exact C++ ownership must not cross classes, declaration trees, or requests. */
class M14CppTypedProgramProjectionTest {
	static function reject(action:Void->Void, label:String):Void {
		try {
			action();
		} catch (_:haxe.Exception) {
			return;
		}
		throw "C++ accepted invalid program ownership: " + label;
	}

	static function module():TypedModule {
		final source = 'class Helper {
 public static var value:Int = 2;
 public static function read():Int return value;
}
class Main {
 static var value:Int = 1;
 static function read():Int return value;
 static function main():Void { Sys.println(read()); }
}';
		final resolved = new ResolvedModule("Main", "Main.hx", ParserStage.parse(source, "Main.hx"));
		final index = TyperIndex.build([resolved]);
		return TyperStage.typeResolvedModule(resolved, index);
	}

	static function main():Void {
		final typed = module();
		final program = new MacroExpandedProgram([typed], false);
		final bound = new CppTypedProgramProjection(program);
		final classes = typed.getBackendProjection().getClasses();
		if (bound.getModules()[0].projection != typed.getBackendProjection()
			|| bound.getProgramRevision() != program.getTypedProgramRevision().getCanonicalIdentity()
			|| bound.getClassGraph().getProgramRevision() != bound.getProgramRevision())
			throw "C++ binding lost its exact program or module";
		for (cls in classes) {
			final declaration = cls.getDeclaration();
			if (bound.requireClass(declaration) != cls)
				throw "C++ class binding changed projection";
			for (fn in cls.getFunctions()) {
				if (bound.requireFunction(declaration, fn.getDeclaration()) != fn)
					throw "C++ function binding changed projection";
				final foreignOwner = classes[0] == cls ? classes[1] : classes[0];
				reject(() -> bound.requireFunction(foreignOwner.getDeclaration(), fn.getDeclaration()), "another class");
			}
			for (initializer in cls.getFieldInitializers()) {
				if (bound.requireInitializer(declaration, initializer.getDeclaration()) != initializer)
					throw "C++ initializer binding changed projection";
				final foreignOwner = classes[0] == cls ? classes[1] : classes[0];
				reject(() -> bound.requireInitializer(foreignOwner.getDeclaration(), initializer.getDeclaration()), "another field owner");
			}
		}
		for (foreign in module().getBackendProjection().getClasses()) {
			reject(() -> bound.requireClass(foreign.getDeclaration()), "another request");
			for (fn in foreign.getFunctions())
				reject(() -> bound.requireFunction(classes[0].getDeclaration(), fn.getDeclaration()), "same source in another request");
		}
		for (legacy in HxModuleDecl.getClasses(typed.getBackendDeclaration()))
			reject(() -> bound.requireClass(legacy), "legacy declaration tree");
		reject(() -> new CppTypedProgramProjection(new MacroExpandedProgram([typed, typed], false)), "duplicate module contribution");
		bound.assertCurrent();
		bound.assertRuntimeTypeOperandsAbsent();
		final parsedFunction = typed.getTypedClasses()[0].getFunctions()[0].getSourceDeclaration();
		HxFunctionDecl.getBody(parsedFunction).push(SExpr(EInt(99), HxPos.unknown()));
		reject(() -> bound.assertCurrent(), "source changed after binding");
		reject(() -> new CppTypedProgramProjection(program), "source changed before binding");
		Sys.println("CPP_TYPED_PROGRAM_PROJECTION:PASS");
	}
}
