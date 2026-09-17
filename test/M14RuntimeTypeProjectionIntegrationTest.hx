/** Proves exact runtime type occurrence ownership across executable projections. */
class M14RuntimeTypeProjectionIntegrationTest {
	static function reject(action:Void->Void, label:String):Void {
		try {
			action();
		} catch (_:haxe.Exception) {
			return;
		}
		throw "invalid runtime type projection accepted: " + label;
	}

	static function returned(fn:TypedBackendFunctionProjection):HxExpr {
		for (statement in fn.getBody())
			switch (statement) {
				case SReturn(value, _):
					return value;
				case _:
			}
		throw "missing projected return";
	}

	static function main():Void {
		final parsed = ParserStage.parse('class Parent {
 public static var answer:Int = 7;
 public static function read():Int { return answer; }
 public static dynamic function word():String { return "before"; }
}
class Main {
 static var selected:Class<Parent> = Parent;
 static var other:Class<Parent> = Parent;
 static function first():Class<Parent> { return Parent; }
 static function second():Class<Parent> { return Parent; }
 static function check(value:Parent):Bool { return value is Parent; }
 static function ordinaryField():Int { return Parent.answer; }
 static function ordinaryCall():Int { return Parent.read(); }
 static function ordinaryQualifiedCall():Int { return Main.Parent.read(); }
 static function ordinaryMethodValue():Void { var callback = Parent.word; }
 static function ordinaryMethodWrite():Void { Parent.word = function():String return "after"; }
 static function ordinaryDynamicCall():String { return Parent.word(); }
}', "Main.hx");
		final resolved = new ResolvedModule("Main", "Main.hx", parsed);
		final index = TyperIndex.build([resolved]);
		final loader = new ModuleLoader(["."], new haxe.ds.StringMap<String>(), index, function(_):Bool return false);
		loader.markResolvedAlready([resolved]);
		final module = TyperStage.typeResolvedModule(resolved, index, loader);
		final projection = module.getBackendProjection();
		var owner:Null<TypedBackendClassProjection> = null;
		for (candidate in projection.getClasses())
			if (candidate.requireSemanticFacts().getClassIdentity() == "Main")
				owner = candidate;
		if (owner == null)
			throw "missing projected Main";
		final functions = new haxe.ds.StringMap<TypedBackendFunctionProjection>();
		for (fn in owner.getFunctions())
			functions.set(HxFunctionDecl.getName(fn.getDeclaration()), fn);
		final first = functions.get("first");
		for (name in [
			"ordinaryField",
			"ordinaryCall",
			"ordinaryQualifiedCall",
			"ordinaryMethodValue",
			"ordinaryMethodWrite",
			"ordinaryDynamicCall"
		])
			if (functions.get(name).getRuntimeTypeCatalog().getEntries().length != 0)
				throw "a statically selected member must not require a runtime class object: " + name;
		final qualifiedCall = TypedExactStaticCallSource.decode(returned(functions.get("ordinaryQualifiedCall")));
		if (qualifiedCall == null || !qualifiedCall.callee.match(EField(EField(EIdent("Main"), "Parent"), "read")))
			throw "an explicitly qualified static owner must remain a structural path";
		final second = functions.get("second");
		final check = functions.get("check");
		final firstMarker = returned(first);
		final firstOccurrence = first.requireRuntimeType(firstMarker);
		if (firstOccurrence.getTarget().requireDeclarationIdentity().getCanonicalName() != "Main.Parent"
			|| firstOccurrence.getValue() != null)
			throw "class value projection lost its exact target";
		final testMarker = returned(check);
		final testOccurrence = check.requireRuntimeType(testMarker);
		if (testOccurrence.getValue() == null
			|| testOccurrence.getTarget().requireDeclarationIdentity().getCanonicalName() != "Main.Parent")
			throw "type-test projection lost its value or exact target";
		switch (testMarker) {
			case ECall(EIdent(TypedRuntimeTypeSource.TEST), arguments):
				if (arguments.length != 1 || arguments[0] != testOccurrence.getValue())
					throw "type test must evaluate exactly one original value";
			case _:
				throw "type test lost its structural marker";
		}
		reject(() -> second.requireRuntimeType(firstMarker), "another function");
		reject(() -> first.requireRuntimeType(ECall(EIdent(TypedRuntimeTypeSource.VALUE), [])), "structural copy");
		reject(() -> first.getRuntimeTypeCatalog().require(firstMarker, first.getStableIdentity(), "stale"), "stale revision");
		reject(() -> new TypedBackendRuntimeTypeCatalog("foreign", first.getBodyRevision(), first.getRuntimeTypeCatalog().getEntries()),
			"foreign catalog owner");
		reject(() -> new TypedBackendRuntimeTypeCatalog(first.getStableIdentity(), "stale", first.getRuntimeTypeCatalog().getEntries()),
			"stale catalog revision");
		final again = TypedBodySource.moduleProjection(module.getParsed(), module.getTypedClasses());
		for (cls in again.getClasses())
			for (fn in cls.getFunctions())
				if (fn.getStableIdentity() == first.getStableIdentity())
					reject(() -> fn.requireRuntimeType(firstMarker), "another projection of the same body");
		final initializers = owner.getFieldInitializers();
		if (initializers.length != 2)
			throw "missing field initializer projections";
		final fieldMarker = initializers[0].getExpression();
		final fieldOccurrence = initializers[0].requireRuntimeType(fieldMarker);
		if (fieldOccurrence.getTarget().requireDeclarationIdentity().getCanonicalName() != "Main.Parent")
			throw "field initializer lost target identity";
		reject(() -> initializers[1].requireRuntimeType(fieldMarker), "another initializer");
		reject(() -> initializers[0].requireRuntimeType(firstMarker), "function marker in initializer");
		reject(() -> first.requireRuntimeType(fieldMarker), "initializer marker in function");
		reject(() -> module.getBackendDeclaration(), "declaration-only consumer");
		reject(() -> projection.assertRuntimeTypeOperandsAbsent("test backend"), "unsupported target");
		// Source-shaped arrays remain mutable during backend migration. Ownership
		// checks must reject a marker removed from its body's current structure.
		final body = HxFunctionDecl.getBody(first.getDeclaration());
		body.splice(0, body.length);
		reject(() -> first.requireRuntimeType(firstMarker), "removed occurrence");
		switch (testMarker) {
			case ECall(_, arguments):
				arguments.push(ENull);
			case _:
		}
		reject(() -> check.requireRuntimeType(testMarker), "mutated arguments");
		final builder = new TypedRuntimeTypeProjectionBuilder("owner", "revision");
		final target = new TypedRuntimeTypeTarget(Nominal(new TyNominalTypeId("Main.Parent")));
		builder.project(target);
		final retained = builder.project(target);
		final catalog = builder.seal([retained]);
		if (catalog.getEntries().length != 1)
			throw "discarded projection intermediate entered the catalog";
		reject(() -> builder.project(target), "write after seal");
		reject(() -> new TypedRuntimeTypeProjectionBuilder("owner", "revision").seal([retained]), "foreign builder marker");
		if (TypedRuntimeTypeSource.isMarker(EString(TypedRuntimeTypeSource.VALUE)))
			throw "ordinary string became a marker";
		Sys.println("RUNTIME_TYPE_PROJECTION:PASS");
	}
}
