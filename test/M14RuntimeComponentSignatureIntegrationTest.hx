import hxhx.macro.MacroHostClient;
import hxhx.macro.MacroState;
import hxhxmacrohost.HostToCompilerRpc;
import hxhxmacrohost.Protocol;
import hxhxmacrohost.api.RuntimeMacroTypes;

class M14RuntimeComponentSignatureIntegrationTest {
	static function fail(message:String):Void {
		throw message;
	}

	static function assertContains(label:String, actual:String, expected:String):Void {
		if (actual.indexOf(expected) >= 0)
			return;
		fail(label + ': expected "' + expected + '" in "' + actual + '"');
	}

	static function main():Void {
		MacroState.reset();
		MacroState.seedFromCliDefines(["reflaxe-target=ocaml", "target.name=ocaml"]);
		MacroState.seedCompilerConfiguration([], ["test/fixtures/hxhx-macros/src"], "ocaml");
		MacroState.addClassPath("test/fixtures/hxhx-macros/src");
		HostToCompilerRpc.setLocalHandler(function(method:String, tail:String):String {
			return switch (method) {
				case "context.getType":
					MacroHostClient.encodeContextGetTypePayload(Protocol.kvGet(tail, "n"));
				case _:
					throw "unexpected local reverse RPC in component signature test: " + method;
			};
		});

		try {
			final path = "test/fixtures/hxhx-macros/src/hxhxmacros/RuntimeComponentModule.hx";
			final fields:Dynamic = MacroHostClient.scanResolvedModuleFields(path);
			final resolvedFields:Array<Dynamic> = cast fields;
			final entries:Array<Dynamic> = cast MacroHostClient.scanResolvedModuleTypes("hxhxmacros.RuntimeComponentModule", path, "RuntimeComponentModule",
				resolvedFields.length == 0);
			final imports:Array<Dynamic> = cast MacroHostClient.scanResolvedModuleImports(path);
			final types = RuntimeMacroTypes.moduleTypesForModule("hxhxmacros.RuntimeComponentModule", cast entries, cast resolvedFields, cast imports);

			var cardTypeSummary:Null<String> = null;
			var cardTypeString:Null<String> = null;
			var cardAssignsFollowSummary:Null<String> = null;
			var slotArityMismatch:Null<String> = null;

			for (t in types) {
				final clsRef = RuntimeMacroTypes.classRefOf(t);
				if (clsRef == null || clsRef.get().name != "Components")
					continue;
				for (field in clsRef.get().statics.get()) {
					if (field.name != "card")
						continue;
					cardTypeSummary = RuntimeMacroTypes.describeTypeShape(field.type, 10);
					cardTypeString = RuntimeMacroTypes.toString(field.type);
					slotArityMismatch = RuntimeMacroTypes.firstTypeParameterArityMismatch(field.type);
					cardAssignsFollowSummary = RuntimeMacroTypes.followedAnonymousFieldSummaryWithAbstracts(switch (field.type) {
						case TFun(args, _):
							args.length == 0 ? null : args[0].t;
						case _:
							null;
					});
				}
			}

			if (cardTypeSummary == null)
				fail("missing Components.card synthetic signature");
			if (slotArityMismatch != null)
				fail("unexpected type parameter arity mismatch: " + slotArityMismatch + " summary=" + cardTypeSummary);
			if (cardAssignsFollowSummary == null)
				fail("followWithAbstracts(assigns) did not produce anonymous fields");

			assertContains("component signature summary", cardTypeSummary, "fun(assigns:abstract:hxhxmacros.RuntimeComponentSupport.Assigns<");
			assertContains("component signature summary", cardTypeSummary, "typedef:hxhxmacros.RuntimeComponentModule.CardAssigns=>anon{");
			assertContains("component signature summary", cardTypeSummary,
				"header:abstract:hxhxmacros.RuntimeComponentSupport.Slot<typedef:hxhxmacros.RuntimeComponentModule.HeaderSlotProps=>anon{label:inst:String},typedef:hxhxmacros.RuntimeComponentModule.HeaderLet=>anon{count:inst:Int,userName:inst:String}>");
			assertContains("component signature summary", cardTypeSummary, ")->inst:String");
			assertContains("component signature string", cardTypeString, "Assigns<");
			assertContains("component signature string", cardTypeString, "CardAssigns");
			assertContains("followed assigns summary", cardAssignsFollowSummary, "title:String");
			assertContains("followed assigns summary", cardAssignsFollowSummary, "header:");
			assertContains("followed assigns summary", cardAssignsFollowSummary, "Slot<");
			assertContains("followed assigns summary", cardAssignsFollowSummary, "HeaderSlotProps");
			assertContains("followed assigns summary", cardAssignsFollowSummary, "HeaderLet");
			assertContains("followed assigns summary", cardAssignsFollowSummary, "inner_content:String");
		} catch (e:Dynamic) {
			HostToCompilerRpc.clearLocalHandler();
			MacroState.reset();
			throw e;
		}
		HostToCompilerRpc.clearLocalHandler();
		MacroState.reset();
	}
}
