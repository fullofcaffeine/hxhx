import reflaxe.ocaml.lowered.OcamlGenericCallConversion.OcamlGenericValueShape;
import reflaxe.ocaml.lowered.OcamlRepresentationRegistry;
import reflaxe.ocaml.lowered.OcamlRepresentationModel.OcamlRepresentationDomain;
import reflaxe.ocaml.lowered.OcamlRepresentationModel.OcamlRepresentationIdentityPolicy;
import reflaxe.ocaml.lowered.OcamlRepresentationModel.OcamlRepresentationStorageMutationPolicy;

/**
	Exercises the target registry without upstream compiler objects or host defines.

	Both interpreted and compiled Haxe must use the same callback layouts and reject
	stale requests. This is a storage contract; it does not prove callback producers
	or authorize the native compiler to emit calls from type annotations alone.
**/
class OrdinaryRepresentationRegistryTest {
	static function require(condition:Bool, message:String):Void {
		if (!condition)
			throw message;
	}

	/** Require the intended registry rejection, not an unrelated runtime exception. */
	static function rejects(diagnostic:String, action:Void->Void):Void {
		try {
			action();
		} catch (error:haxe.Exception) {
			require(error.message.indexOf(diagnostic) >= 0, 'Expected $diagnostic, got ${error.message}');
			return;
		}
		throw 'Expected $diagnostic to reject the request';
	}

	static function main():Void {
		final registry = new OcamlRepresentationRegistry();
		final shape = FunctionValue([DynamicValue], DynamicValue);
		rejects("beginProgram", () -> registry.selectCallableView(shape, InternalValue));
		registry.beginProgram("ordinary-callback-program");
		final selected = registry.selectCallableView(shape, InternalValue);
		final layout = registry.requireCallableView(selected.id, selected.revision, "ordinary-callback-program");
		require(layout.semanticTypeId == "(Dynamic)->Dynamic", "The stored function signature must remain explicit");
		require(layout.carrierTypeId == "callable-view<(Dynamic)->Dynamic>", "Callbacks must retain their identity-bearing carrier");
		require(selected.identityPolicy == ReferenceIdentity, "A signature conversion must not replace function identity");
		require(selected.storageMutationPolicy == ImmutableBinding, "Internal values must not acquire mutable local storage");
		final repeated = registry.selectCallableView(shape, InternalValue);
		require(repeated.id == selected.id && repeated.revision == selected.revision, "Repeated selection must reuse the registered decision");
		require(registry.decisions().length == 1, "Repeated selection must not add another storage owner");

		for (domain in [MutableLocalStorage, CapturedLocalStorage]) {
			final local = registry.selectCallableView(shape, domain);
			final localLayout = registry.requireCallableView(local.id, local.revision, "ordinary-callback-program");
			require(local.id != selected.id && local.domain == domain, "Each local storage domain needs its own registered decision");
			require(local.storageMutationPolicy == SharedLocalCell, "Writable callback locals must share one cell");
			require(localLayout.revision == layout.revision, "Storage ownership must not change the invocation or identity layout");
		}

		final nested = registry.selectCallableView(FunctionValue([shape], FunctionValue([Integer], DynamicValue)), InternalValue);
		final nestedLayout = registry.requireCallableView(nested.id, nested.revision, "ordinary-callback-program");
		require(nestedLayout.semanticTypeId == "((Dynamic)->Dynamic)->(Int)->Dynamic", "Higher-order callbacks must retain both nested signatures");
		// Public arrays belong to the caller. Changing them must not corrupt retained layouts.
		switch (nestedLayout.shape) {
			case FunctionValue(arguments, _):
				arguments[0] = Boolean;
			case _:
				throw "Expected a function descriptor";
		}
		require(registry.requireCallableView(nested.id, nested.revision, "ordinary-callback-program").revision == nestedLayout.revision,
			"Caller edits must not change the registered callback signature");
		rejects("unproved-domain", () -> registry.selectCallableView(shape, InstanceField));
		rejects("unproved-carrier", () -> registry.selectCallableView(FunctionValue([ArrayValue(Integer)], DynamicValue), InternalValue));
		rejects("missing-layout", () -> registry.requireCallableView(selected.id, "changed-revision", "ordinary-callback-program"));
		rejects("stale-program-revision", () -> registry.requireCallableView(selected.id, selected.revision, "another-program"));
		final integer = registry.selectExactInt(InternalValue);
		rejects("missing-layout", () -> registry.requireCallableView(integer.id, integer.revision, "ordinary-callback-program"));

		registry.beginProgram("next-program");
		require(registry.decisions().length == 0, "A new compilation request must discard old storage decisions");
		rejects("missing-decision", () -> registry.requireCallableView(selected.id, selected.revision, "next-program"));
		rejects("stale-program-revision", () -> registry.requireCallableView(selected.id, selected.revision, "ordinary-callback-program"));
		Sys.println("OCAML_ORDINARY_REPRESENTATION_REGISTRY:PASS");
	}
}
