import backend.cpp.CppTypedProgramProjection;

/** Binding ownership and emitted spelling must remain separate across executable bodies. */
class M14CppExecutableLocalsTest {
	static function reject(action:Void->Void, label:String):Void {
		try {
			action();
		} catch (_:haxe.Exception) {
			return;
		}
		throw "C++ local plan accepted " + label;
	}

	static function module():TypedModule {
		final source = 'class Main {
 static var field:Int = 10;
 static var initialized:Int = { var int = 3; var int_ = 4; int + int_; };
 static function first(z:Int, a:String, b:Int, c:Int, d:Int, e:Int, f:Int, g:Int, h:Int, i:Int, j:Int, k:Int):Int {
  var int = z; var int_:String = a; var int__2 = true;
  var template = 1; var template_ = 2;
  return int + field;
 }
 static function second(int:String):String return int;
}
class Other { static function first(int:Int):Int return int; }';
		final resolved = new ResolvedModule("Main", "Main.hx", ParserStage.parse(source, "Main.hx"));
		return TyperStage.typeResolvedModule(resolved, TyperIndex.build([resolved]));
	}

	static function main():Void {
		final typed = module();
		final bound = new CppTypedProgramProjection(new MacroExpandedProgram([typed], false));
		final classes = typed.getBackendProjection().getClasses();
		final cls = classes[0];
		if (bound.requireClassIdentity("Main") != cls.getDeclaration()
			|| bound.requireClassIdentity("Main.Other") != classes[1].getDeclaration())
			throw "C++ selected class ownership lost its canonical module identity";
		reject(() -> bound.requireClassIdentity("Other"), "a short-name substitute for a selected class");
		final first = cls.getFunctions()[0];
		final second = cls.getFunctions()[1];
		final plan = bound.functionLocals(cls.getDeclaration(), first.getDeclaration());
		if (plan.requireFunction() != first
			|| plan.getStableIdentity() != first.getStableIdentity()
			|| plan.getBodyRevision() != first.getBodyRevision()
			|| plan.getFieldReadCatalog() != first.getFieldReadCatalog())
			throw "C++ local plan lost its exact executable or field facts";
		final parameters = plan.getParameters();
		if (parameters.length != 12
			|| parameters[0].getProjectedName() != "z"
			|| parameters[1].getProjectedName() != "a"
			|| parameters[2].getProjectedName() != "b"
			|| parameters[10].getProjectedName() != "j")
			throw "C++ parameter order changed";
		parameters.pop();
		if (plan.getParameters().length != 12)
			throw "C++ exposed mutable parameter inventory";
		if (plan.symbol("int_") != "int_" || plan.symbol("int__2") != "int__2" || plan.symbol("int") == "int_" || plan.symbol("int") == "int__2")
			throw "C++ collision allocation replaced an explicit safe name";
		if (plan.symbol("template") == "template" || plan.symbol("template") == "template_" || plan.symbol("template_") != "template_")
			throw "C++ accepted a keyword or replaced its safe neighbor";
		final occupied = new haxe.ds.StringMap<Bool>();
		for (local in first.getLocalCatalog().getEntries()) {
			final name = local.getProjectedName();
			final symbol = plan.symbol(name);
			if (occupied.exists(symbol)
				|| plan.requireIdentity(local.getBinding().getIdentity()) != local
				|| plan.findLocal(name) != local)
				throw "C++ local plan lost a unique exact binding";
			occupied.set(symbol, true);
			if (plan.symbol(name) != symbol)
				throw "C++ lookup changed a planned symbol";
		}
		final repeated = bound.functionLocals(cls.getDeclaration(), first.getDeclaration());
		if (repeated.symbol("int") != plan.symbol("int"))
			throw "C++ repeated planning changed symbols";
		final reserved = bound.functionLocals(cls.getDeclaration(), first.getDeclaration(), ["z", "int__3"]);
		if (reserved.symbol("z") == "z" || reserved.symbol("int") == "int__3" || reserved.symbol("int_") != "int_")
			throw "C++ ignored fixed environment symbols";
		final temporaries = new backend.cpp.CppTemporarySymbols(reserved);
		final authoredSymbol = reserved.symbol("int");
		final temporary = temporaries.symbol(authoredSymbol);
		final neighboringTemporary = temporaries.symbol(temporary);
		if (temporary == authoredSymbol
			|| reserved.getOccupiedSymbols().indexOf(temporary) >= 0
			|| neighboringTemporary == temporary
			|| temporaries.symbol(authoredSymbol) != temporary
			|| reserved.symbol("int") != authoredSymbol
			|| temporaries.symbol("z") == "z")
			throw "C++ temporary allocation replaced authored, fixed, or previously allocated storage";
		final other = bound.functionLocals(cls.getDeclaration(), second.getDeclaration());
		if (other.findLocal("int") == plan.findLocal("int"))
			throw "C++ reused a binding from another executable";
		reject(() -> plan.requireIdentity(other.findLocal("int").getBinding().getIdentity()), "another executable identity");
		reject(() -> bound.functionLocals(classes[1].getDeclaration(), first.getDeclaration()), "another class");
		final foreign = module().getBackendProjection().getClasses()[0];
		reject(() -> bound.functionLocals(cls.getDeclaration(), foreign.getFunctions()[0].getDeclaration()), "another request");
		reject(() -> plan.requireIdentity(foreign.getFunctions()[0].getLocalCatalog().findByProjectedName("int").getBinding().getIdentity()),
			"same canonical identity from another request");
		reject(() -> bound.functionLocals(cls.getDeclaration(), first.getDeclaration(), [""]), "empty fixed environment symbol");
		reject(() -> plan.symbol("missing"), "an unknown local spelling");
		reject(() -> plan.symbol("field"), "a bare field as a local");
		if (plan.getFieldReadCatalog().findByProjectedName("field") == null)
			throw "C++ local plan lost a selected bare field";
		final initializer = cls.getFieldInitializers()[1];
		final init = bound.initializerLocals(cls.getDeclaration(), initializer.getDeclaration());
		if (init.requireInitializer() != initializer
			|| init.getParameters().length != 0
			|| init.getBodyRevision() != initializer.getBodyRevision())
			throw "C++ initializer plan borrowed a function owner";
		for (local in initializer.getLocalCatalog().getEntries())
			if (init.requireIdentity(local.getBinding().getIdentity()) != local)
				throw "C++ rejected exact initializer membership";
		reject(() -> plan.requireInitializer(), "function as initializer");
		reject(() -> init.requireFunction(), "initializer as function");
		reject(() -> init.requireIdentity(plan.findLocal("int").getBinding().getIdentity()), "function identity in initializer");
		Sys.println("CPP_EXECUTABLE_LOCALS:PASS");
	}
}
