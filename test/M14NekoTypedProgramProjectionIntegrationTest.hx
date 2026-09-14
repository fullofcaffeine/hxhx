import backend.vm.NekoTypedProgramProjection;
import backend.vm.NekoExactCallPlan;

/** Checks exact secondary-type ownership through the normal indexed typer. */
class M14NekoTypedProgramProjectionIntegrationTest {
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
		final parsed = ParserStage.parse(source, "Main.hx");
		final resolved = new ResolvedModule("Main", "Main.hx", parsed);
		final index = TyperIndex.build([resolved]);
		final loader = new ModuleLoader(["."], new haxe.ds.StringMap<String>(), index, function(_):Bool return false);
		loader.markResolvedAlready([resolved]);
		final typed = TyperStage.typeResolvedModule(resolved, index, loader);
		final module = typed.getBackendProjection();
		final projection = new NekoTypedProgramProjection([module]);
		final owner = projection.requireClass("Main.Flavor");
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
		Sys.println("OK m14 Neko typed program projection");
	}
}
