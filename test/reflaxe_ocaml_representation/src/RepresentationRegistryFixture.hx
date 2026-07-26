#if macro
import haxe.macro.Context;
import haxe.macro.Type;
import reflaxe.ocaml.lowered.OcamlRepresentationModel.OcamlRepresentationAliasingPolicy;
import reflaxe.ocaml.lowered.OcamlRepresentationModel.OcamlRepresentationBoxingPolicy;
import reflaxe.ocaml.lowered.OcamlRepresentationModel.OcamlRepresentationDomain;
import reflaxe.ocaml.lowered.OcamlRepresentationModel.OcamlRepresentationIdentityPolicy;
import reflaxe.ocaml.lowered.OcamlRepresentationModel.OcamlRepresentationNullPolicy;
import reflaxe.ocaml.lowered.OcamlRepresentationModel.OcamlRepresentationStorageMutationPolicy;
import reflaxe.ocaml.lowered.OcamlRepresentationModel.OcamlRepresentationValueMutationPolicy;
import reflaxe.ocaml.lowered.OcamlRepresentationRegistry;

/** Focused executable checks for the program-wide OCaml representation registry. */
class RepresentationRegistryFixture {
	static function assertTrue(condition:Bool, message:String):Void {
		if (!condition)
			throw message;
	}

	static function expectFailure(label:String, expectedMessage:String, action:Void->Void):Void {
		var failed = false;
		try {
			action();
		} catch (error:Dynamic) {
			failed = true;
			final message = Std.string(error);
			if (message.indexOf(expectedMessage) < 0)
				throw '$label failed with an unexpected message: $message';
		}
		if (!failed)
			throw '$label should have failed.';
	}

	/** Runs during compilation so exact built-in Haxe types are available. */
	public static function run():Void {
		final registry = new OcamlRepresentationRegistry();
		expectFailure("unstarted registry", "beginProgram", () -> registry.selectExactInt(OcamlRepresentationDomain.InternalValue));

		registry.beginProgram("program:representation-fixture");
		assertTrue(OcamlRepresentationRegistry.isExactInt(Context.typeof(macro(0 : Int))), "the built-in non-null Int should be admitted");
		assertTrue(!OcamlRepresentationRegistry.isExactInt(Context.typeof(macro(0.0 : Float))), "Float should remain outside the first slice");
		assertTrue(!OcamlRepresentationRegistry.isExactInt(Context.typeof(macro(null : Null<Int>))), "nullable Int should remain outside the first slice");
		assertTrue(OcamlRepresentationRegistry.isExactArrayInt(Context.typeof(macro([] : Array<Int>))), "the direct nominal Array<Int> should be admitted");
		assertTrue(!OcamlRepresentationRegistry.isExactArrayInt(Context.typeof(macro([] : Array<Float>))),
			"Array<Float> should remain outside the exact Array<Int> slice");
		assertTrue(!OcamlRepresentationRegistry.isExactArrayInt(Context.typeof(macro(null : Null<Array<Int>>))),
			"an explicit nullable Array<Int> wrapper should remain outside the slice");
		assertTrue(!OcamlRepresentationRegistry.isExactArrayInt(Context.typeof(macro([] : IntArrayAlias))),
			"an Array<Int> typedef should need its own representation proof instead of being followed implicitly");
		assertTrue(!OcamlRepresentationRegistry.isExactArrayInt(Context.typeof(macro(new haxe.ds.Vector<Int>(1)))),
			"Vector<Int> should not inherit the direct nominal Array<Int> carrier");
		final genericArrayType = switch (Context.getType("GenericArrayCarrier")) {
			case TInst(classRef, _):
				final values = classRef.get().fields.get().filter(field -> field.name == "values");
				if (values.length != 1)
					throw "GenericArrayCarrier.values should resolve exactly once.";
				values[0].type;
			case other:
				throw 'GenericArrayCarrier should be a class, got $other';
		}
		assertTrue(!OcamlRepresentationRegistry.isExactArrayInt(genericArrayType), "Array<T> should remain outside the exact Array<Int> representation proof");

		final mutable = registry.selectExactInt(OcamlRepresentationDomain.MutableLocalStorage);
		final internal = registry.selectExactInt(OcamlRepresentationDomain.InternalValue);
		final captured = registry.selectExactInt(OcamlRepresentationDomain.CapturedLocalStorage);
		final arrayInternal = registry.selectExactArrayInt(OcamlRepresentationDomain.InternalValue);
		final arrayMutable = registry.selectExactArrayInt(OcamlRepresentationDomain.MutableLocalStorage);
		final arrayCaptured = registry.selectExactArrayInt(OcamlRepresentationDomain.CapturedLocalStorage);
		assertTrue(mutable.semanticTypeId == "Int" && mutable.carrierTypeId == "int", "exact Int storage should use the direct OCaml int carrier");
		assertTrue(mutable.proof.id == "direct-exact-int-storage-64-v1"
			&& mutable.proof.claim.indexOf("still require HxInt") >= 0
			&& mutable.proof.claim.indexOf("does not admit a 32-bit OCaml target") >= 0,
			"the direct carrier proof should remain limited to storage on the tested 64-bit target hosts");
		assertTrue(mutable.storageMutationPolicy == OcamlRepresentationStorageMutationPolicy.SharedLocalCell
			&& mutable.valueMutationPolicy == OcamlRepresentationValueMutationPolicy.ImmutableValue,
			"mutable Int storage should explain that its surrounding ref cell owns mutation");
		assertTrue(internal.storageMutationPolicy == OcamlRepresentationStorageMutationPolicy.ImmutableBinding
			&& internal.valueMutationPolicy == OcamlRepresentationValueMutationPolicy.ImmutableValue,
			"an internal Int should separate immutable binding storage from immutable value behavior");
		assertTrue(captured.storageMutationPolicy == OcamlRepresentationStorageMutationPolicy.SharedLocalCell,
			"a captured Int should use the one cell shared with nested functions");
		assertTrue(mutable.id == "representation:Int:mutable-local-storage", "representation identities should be semantic and program independent");
		assertTrue(arrayInternal.semanticTypeId == "Array<Int>" && arrayInternal.carrierTypeId == "int HxArray.t",
			"the direct Array<Int> internal value should use the typed HxArray carrier");
		assertTrue(arrayInternal.nullPolicy == OcamlRepresentationNullPolicy.RuntimeSentinel
			&& arrayInternal.identityPolicy == OcamlRepresentationIdentityPolicy.ReferenceIdentity
			&& arrayInternal.aliasingPolicy == OcamlRepresentationAliasingPolicy.SharedReferenceAliases
			&& arrayInternal.storageMutationPolicy == OcamlRepresentationStorageMutationPolicy.ImmutableBinding
			&& arrayInternal.valueMutationPolicy == OcamlRepresentationValueMutationPolicy.MutableRuntimeContainer
			&& arrayInternal.boxingPolicy == OcamlRepresentationBoxingPolicy.DirectRuntimeContainer,
			"the Array<Int> decision should separate immutable binding replacement from shared array mutation");
		assertTrue(arrayMutable.storageMutationPolicy == OcamlRepresentationStorageMutationPolicy.SharedLocalCell
			&& arrayCaptured.storageMutationPolicy == OcamlRepresentationStorageMutationPolicy.SharedLocalCell
			&& arrayMutable.valueMutationPolicy == OcamlRepresentationValueMutationPolicy.MutableRuntimeContainer,
			"mutable and captured Array<Int> locals should separate ref-cell replacement from container mutation");
		assertTrue(arrayInternal.proof.id == "direct-array-int-reference-carrier-v2"
			&& arrayInternal.proof.claim.indexOf("does not admit generic") >= 0,
			"the Array<Int> proof should name its narrow boundary instead of generalizing all arrays");
		assertTrue(registry.require(mutable.id, "program:representation-fixture").revision == mutable.revision,
			"an exact-program lookup should return the selected decision");

		final repeated = registry.selectExactInt(OcamlRepresentationDomain.MutableLocalStorage);
		assertTrue(repeated.revision == mutable.revision
			&& registry.decisions().length == 6, "selecting the same answer twice should reuse one decision");
		final ordered = registry.decisions();
		assertTrue(ordered[0].id < ordered[1].id && ordered[1].id < ordered[2].id, "reported decisions should use deterministic identity order");

		mutable.profileEligibility.push("changed-by-caller");
		assertTrue(registry.require(mutable.id, "program:representation-fixture").profileEligibility.join(",") == "metal,portable",
			"mutating a returned profile list must not change the retained decision");

		expectFailure("missing decision", "no representation decision exists",
			() -> registry.require("representation:Int:missing", "program:representation-fixture"));
		expectFailure("stale program", "registry belongs to", () -> registry.require(internal.id, "program:older"));
		expectFailure("unsupported Array<Int> domain", "admitted only for internal, mutable-local, or captured-local storage",
			() -> registry.selectExactArrayInt(OcamlRepresentationDomain.InstanceField));
		expectFailure("conflicting carrier", "cannot also use Obj.t", () -> registry.register({
			semanticTypeId: mutable.semanticTypeId,
			domain: mutable.domain,
			carrierTypeId: "Obj.t",
			nullPolicy: mutable.nullPolicy,
			identityPolicy: mutable.identityPolicy,
			aliasingPolicy: mutable.aliasingPolicy,
			storageMutationPolicy: mutable.storageMutationPolicy,
			valueMutationPolicy: mutable.valueMutationPolicy,
			boxingPolicy: mutable.boxingPolicy,
			reason: mutable.reason,
			proof: mutable.proof,
			profileEligibility: mutable.profileEligibility
		}));

		final registryAgain = new OcamlRepresentationRegistry();
		registryAgain.beginProgram("program:representation-fixture");
		registryAgain.selectExactInt(OcamlRepresentationDomain.CapturedLocalStorage);
		registryAgain.selectExactInt(OcamlRepresentationDomain.InternalValue);
		registryAgain.selectExactInt(OcamlRepresentationDomain.MutableLocalStorage);
		registryAgain.selectExactArrayInt(OcamlRepresentationDomain.InternalValue);
		registryAgain.selectExactArrayInt(OcamlRepresentationDomain.MutableLocalStorage);
		registryAgain.selectExactArrayInt(OcamlRepresentationDomain.CapturedLocalStorage);
		assertTrue(registryAgain.revision() == registry.revision(), "registration order should not change the registry revision");

		registry.beginProgram("program:new-request");
		expectFailure("request reset", "no representation decision exists", () -> registry.require(internal.id, "program:new-request"));
		Sys.println("REFLAXE_OCAML_REPRESENTATION_REGISTRY_FIXTURE:PASS");
	}
}
#end
