/** Backends must receive exact applied constructors from functions and field initializers. */
class M14ConstructorProjectionTest {
	static function reject(action:Void->Void, expected:String):Void {
		try {
			action();
		} catch (error:haxe.Exception) {
			if (error.message.indexOf(expected) < 0)
				throw error;
			return;
		}
		throw "constructor projection accepted " + expected;
	}

	static function main():Void {
		final source = 'class Main {
 static var field:Box<String> = new Box<String>("field");
 static var grouped:Box<String> = { var value = new Box<String>("group"); value; };
 static function first():Box<String> { return new Box<String>("first"); }
 static function second():Box<String> { return new Box<String>("second"); }
 static function nested():Void { var make = function():Box<Int> return new Box<Int>(3); }
 static function choose(value:String):String { return value; }
 static function argument():Box<String> { return new Box<String>(choose("input")); }
 static function quoted():Void { var syntax = macro new Box<String>("quoted"); }
 static function unresolved():Void { var invalid = new Box<Int>("wrong"); }
}
abstract Box<T>(T) { public function new(value:T) { this = value; } }';
		final parsed = ParserStage.parse(source, "Main.hx");
		final resolved = new ResolvedModule("Main", "Main.hx", parsed);
		final index = TyperIndex.build([resolved]);
		final module = TyperStage.typeResolvedModule(resolved, index);
		final projection = module.getBackendProjection();
		var owner:Null<TypedBackendClassProjection> = null;
		for (cls in projection.getClasses())
			if (HxClassDecl.getName(cls.getDeclaration()) == "Main")
				owner = cls;
		if (owner == null)
			throw "missing Main projection";
		final functions = new haxe.ds.StringMap<TypedBackendFunctionProjection>();
		for (fn in owner.getFunctions())
			functions.set(HxFunctionDecl.getName(fn.getDeclaration()), fn);
		final first = functions.get("first");
		final second = functions.get("second");
		final firstEntries = first.getConstructorCatalog().getEntries();
		if (firstEntries.length != 1)
			throw "function lost its constructor occurrence";
		final expression = firstEntries[0].getExpression();
		final occurrence = first.requireConstructor(expression);
		final application = occurrence.requireApplication();
		if (application.getUnderlyingType().getSemanticKey() != "primitive:String"
			|| application.getParameterTypes()[0].getSemanticKey() != "primitive:String"
			|| application.getDeclaration().getOwner().getCanonicalName() != "Main.Box")
			throw "projected constructor lost exact generic application";
		final argument = occurrence.getArguments()[0];
		if (!argument.match(EString("first")))
			throw "constructor projection changed its argument";
		if (functions.get("nested").getConstructorCatalog().getEntries()[0].requireApplication().getUnderlyingType().getSemanticKey() != "primitive:Int")
			throw "nested function lost its applied constructor";
		if (functions.get("quoted").getConstructorCatalog().getEntries().length != 0)
			throw "quoted construction became an executable occurrence";
		final unresolved = functions.get("unresolved").getConstructorCatalog().getEntries();
		if (unresolved.length != 1)
			throw "unresolved construction vanished from the catalog";
		reject(() -> unresolved[0].requireApplication(), "unresolved constructor");
		reject(() -> second.requireConstructor(expression), "absent from the current");
		reject(() -> first.requireConstructor(ENew("Box<String>", [argument])), "absent from the current");
		reject(() -> first.getConstructorCatalog().require(expression, first.getStableIdentity(), "stale"), "another executable or revision");
		final again = TypedBodySource.moduleProjection(module.getParsed(), module.getTypedClasses());
		for (cls in again.getClasses())
			for (fn in cls.getFunctions())
				if (fn.getStableIdentity() == first.getStableIdentity())
					reject(() -> fn.requireConstructor(expression), "absent from the current");
		final initializers = owner.getFieldInitializers();
		if (initializers.length != 2)
			throw "missing initializer projections";
		for (initializer in initializers) {
			final entries = initializer.getConstructorCatalog().getEntries();
			if (entries.length != 1
				|| initializer.requireConstructor(entries[0].getExpression())
					.requireApplication()
					.getUnderlyingType()
					.getSemanticKey() != "primitive:String")
				throw "initializer lost exact construction";
			reject(() -> initializer.requireConstructor(expression), "absent from the current");
		}
		// Declaration-only views must carry their own occurrences, including the
		// lowered block initializer, instead of borrowing the strict projection.
		final legacy = TypedBodySource.moduleDeclarationCatalog(module.getParsed(), module.getTypedClasses());
		var legacyCount = 0;
		for (cls in HxModuleDecl.getClasses(legacy.getDeclaration())) {
			for (fn in HxClassDecl.getFunctions(cls))
				for (node in TypedConstructorSource.inStatements(HxFunctionDecl.getBody(fn))) {
					legacy.requireConstructor(node);
					legacyCount++;
				}
			for (field in HxClassDecl.getFields(cls))
				for (node in TypedConstructorSource.inExpression(HxFieldDecl.getInit(field))) {
					legacy.requireConstructor(node).requireApplication();
					legacyCount++;
				}
		}
		if (legacyCount != 7)
			throw "declaration-only view lost constructor occurrences: " + legacyCount;
		reject(() -> legacy.requireConstructor(expression), "absent from the current");
		var legacyFirst:Null<HxFunctionDecl> = null;
		var legacySecond:Null<HxFunctionDecl> = null;
		for (cls in HxModuleDecl.getClasses(legacy.getDeclaration()))
			for (fn in HxClassDecl.getFunctions(cls)) {
				if (HxFunctionDecl.getName(fn) == "first")
					legacyFirst = fn;
				if (HxFunctionDecl.getName(fn) == "second")
					legacySecond = fn;
			}
		final moved = TypedConstructorSource.inStatements(HxFunctionDecl.getBody(legacyFirst))[0];
		final movedStatement = HxFunctionDecl.getBody(legacyFirst).shift();
		HxFunctionDecl.getBody(legacySecond).push(movedStatement);
		reject(() -> legacy.requireConstructor(moved), "not an exact occurrence");
		// Identical syntax in a replacement object cannot inherit a prior call's facts.
		switch expression {
			case ENew(_, arguments):
				arguments[0] = EString("first");
			case _:
				throw "construction lost its ordinary source shape";
		}
		reject(() -> first.requireConstructor(expression), "arguments were replaced");
		final argumentFunction = functions.get("argument");
		final argumentEntry = argumentFunction.getConstructorCatalog().getEntries()[0];
		var changed = false;
		TypedBackendSourceWalk.expression(argumentEntry.getArguments()[0], node -> {
			switch node {
				case ECall(_, values):
					for (index in 0...values.length)
						if (values[index].match(EString("input"))) {
							values[index] = EString("changed");
							changed = true;
						}
				case _:
			}
		});
		if (!changed)
			throw "nested argument mutation probe did not change its input";
		reject(() -> argumentFunction.requireConstructor(argumentEntry.getExpression()), "argument structure was mutated");
		final secondEntry = second.getConstructorCatalog().getEntries()[0];
		HxFunctionDecl.getBody(second.getDeclaration()).resize(0);
		reject(() -> second.requireConstructor(secondEntry.getExpression()), "absent from the current");
		Sys.println("CONSTRUCTOR_PROJECTION:PASS");
	}
}
