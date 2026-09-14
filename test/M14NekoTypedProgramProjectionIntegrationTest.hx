import backend.vm.NekoTypedProgramProjection;
import backend.vm.NekoExactCallPlan;

/** Checks exact secondary-type ownership through the normal indexed typer. */
class M14NekoTypedProgramProjectionIntegrationTest {
	/** Uses the same resolved module and semantic index as normal compilation. */
	static function project(source:String):TypedBackendModuleProjection {
		final parsed = ParserStage.parse(source, "Main.hx");
		final resolved = new ResolvedModule("Main", "Main.hx", parsed);
		final index = TyperIndex.build([resolved]);
		final loader = new ModuleLoader(["."], new haxe.ds.StringMap<String>(), index, function(_):Bool return false);
		loader.markResolvedAlready([resolved]);
		return TyperStage.typeResolvedModule(resolved, index, loader).getBackendProjection();
	}

	static function expectFailure(fragment:String, action:Void->Void):Void {
		try {
			action();
		} catch (error:haxe.Exception) {
			if (error.message.indexOf(fragment) < 0)
				throw "unexpected projection error: " + error.message;
			return;
		}
		throw "expected projection rejection: " + fragment;
	}

	static function main():Void {
		final source = 'enum abstract Flavor(String) { var Bold = "strong"; public function label():String return this; }
class Main { static function main():Void { Sys.println(Flavor.Bold.label()); } }';
		final module = project(source);
		final projection = new NekoTypedProgramProjection([module]);
		final owner = projection.requireClass("Main.Flavor");
		switch (owner.requireSemanticFacts().getNominalKind()) {
			case AbstractValue(underlying):
				if (underlying.getSemanticKey() != "primitive:String")
					throw "the abstract lost its exact String backing type";
			case _:
				throw "the abstract was projected as an ordinary object";
		}
		if (!projection.requireClass("Main").requireSemanticFacts().getNominalKind().match(ClassInstance))
			throw "the ordinary class gained an abstract receiver";
		final declaration = "Main.Flavor#instance:label()->primitive:String#0";
		final selected = projection.requireFunction("Main.Flavor", declaration);
		if (selected.owner != owner || selected.body.getStableIdentity() != declaration)
			throw "the selected helper lost its canonical owner or declaration";
		if (selected.body.getReturnType().getCanonicalDisplay() != "String" || selected.body.getBody().length == 0)
			throw "the selected helper lost its typed result or body";
		expectFailure("cannot find class Flavor", () -> projection.requireClass("Flavor"));
		expectFailure("does not belong to Main", () -> projection.requireFunction("Main", declaration));
		expectFailure("cannot find function missing", () -> projection.requireFunction("Main.Flavor", "missing"));
		expectFailure("duplicate class", () -> new NekoTypedProgramProjection([module, module]));
		final exact = TypedExactCallSource.encodeInstance("Main.Flavor", declaration, "label", "String", EString("strong"), []);
		final call = NekoExactCallPlan.fromExpression(projection, exact);
		if (call == null || call.selected.body != selected.body || call.getArguments().length != 0)
			throw "the exact call did not select the indexed helper body";
		if (NekoExactCallPlan.fromExpression(projection, ECall(EIdent("ordinary"), [])) != null)
			throw "an ordinary call gained an exact declaration";
		expectFailure("malformed typed payload",
			() -> NekoExactCallPlan.fromExpression(projection, ECall(EIdent(TypedExactCallSource.INSTANCE_INTRINSIC), [])));
		expectFailure("conflicts with declaration",
			() -> NekoExactCallPlan.fromExpression(projection,
				TypedExactCallSource.encodeInstance("Main.Flavor", declaration, "different", "String", EString("strong"), [])));
		assertNominalKinds();
		Sys.println("OK m14 Neko typed program projection");
	}

	/** A declaration kind or abstract backing-type change must invalidate the shared facts. */
	static function assertNominalKinds():Void {
		final variants = [
			'class Value {} class Main {}',
			'enum Value { Item; } class Main {}',
			'abstract Value(String) {} class Main {}',
			'abstract Value(Int) {} class Main {}'
		];
		final facts = [
			for (source in variants)
				new NekoTypedProgramProjection([project(source)]).requireClass("Main.Value").requireSemanticFacts()
		];
		if (!facts[0].getNominalKind().match(ClassInstance) || !facts[1].getNominalKind().match(EnumValue))
			throw "ordinary class and enum declarations lost their distinct receiver kinds";
		for (i in 0...facts.length)
			for (j in i + 1...facts.length)
				if (facts[i].getCanonicalIdentity() == facts[j].getCanonicalIdentity())
					throw "a declaration kind or abstract backing-type change reused the same class facts";
		final generic = new NekoTypedProgramProjection([project('class Backing<T> {} abstract Value<T>(Backing<T>) {} class Main {}')])
			.requireClass("Main.Value")
			.requireSemanticFacts();
		switch (generic.getNominalKind()) {
			case AbstractValue(underlying):
				final expected = TyType.nominal(new TyNominalTypeId("Main.Backing"), [TyType.typeParameter(generic.getTypeParameterIds()[0])]);
				if (underlying.getSemanticKey() != expected.getSemanticKey())
					throw "the abstract backing type lost its exact generic binder: "
						+ underlying.getSemanticKey()
						+ " versus "
						+ expected.getSemanticKey();
			case _:
				throw "the generic abstract lost its backing type";
		}
	}
}
