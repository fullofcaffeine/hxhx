#if macro
import haxe.macro.Context;
import haxe.macro.Type;
import reflaxe.ocaml.ast.OcamlConst;
import reflaxe.ocaml.ast.OcamlExpr;
import reflaxe.ocaml.ast.OcamlTypeExpr;
import reflaxe.ocaml.lowered.OcamlFieldRepresentationMaterializer;
import reflaxe.ocaml.lowered.OcamlDirectArraySourceIdentity;
import reflaxe.ocaml.lowered.OcamlRepresentationModel.OcamlRepresentationAliasingPolicy;
import reflaxe.ocaml.lowered.OcamlRepresentationModel.OcamlRepresentationBoxingPolicy;
import reflaxe.ocaml.lowered.OcamlRepresentationModel.OcamlRepresentationDecision;
import reflaxe.ocaml.lowered.OcamlRepresentationModel.OcamlRepresentationDomain;
import reflaxe.ocaml.lowered.OcamlRepresentationModel.OcamlRepresentationIdentityPolicy;
import reflaxe.ocaml.lowered.OcamlRepresentationModel.OcamlRepresentationImplicitDefaultPolicy;
import reflaxe.ocaml.lowered.OcamlRepresentationModel.OcamlRepresentationNullPolicy;
import reflaxe.ocaml.lowered.OcamlRepresentationModel.OcamlNormalizedRepresentedArray;
import reflaxe.ocaml.lowered.OcamlRepresentationModel.OcamlRepresentedArrayDescriptor;
import reflaxe.ocaml.lowered.OcamlRepresentationModel.OcamlRepresentationStorageMutationPolicy;
import reflaxe.ocaml.lowered.OcamlRepresentationModel.OcamlRepresentationValueMutationPolicy;
import reflaxe.ocaml.lowered.OcamlRepresentationRegistry;
import reflaxe.ocaml.lowered.OcamlStringRepresentationMaterializer;

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

	/** Copies and damages one public decision without mutating registry-owned state. */
	static function expectDecisionCorruption(label:String, decision:OcamlRepresentationDecision, expectedMessage:String, mutate:Dynamic->Void):Void {
		final corrupted:Dynamic = Reflect.copy(decision);
		Reflect.setField(corrupted, "proof", Reflect.copy(decision.proof));
		Reflect.setField(corrupted, "profileEligibility", decision.profileEligibility.copy());
		mutate(corrupted);
		expectFailure(label, expectedMessage, () -> OcamlRepresentationRegistry.validateDecisionSnapshot(cast corrupted, "program:representation-fixture"));
	}

	/** Copies and damages one array descriptor before checking its complete element edge. */
	static function expectArrayDescriptorCorruption(label:String, descriptor:OcamlRepresentedArrayDescriptor, element:OcamlRepresentationDecision,
			mutate:Dynamic->Void):Void {
		final corrupted:Dynamic = Reflect.copy(descriptor);
		Reflect.setField(corrupted, "profileEligibility", descriptor.profileEligibility.copy());
		mutate(corrupted);
		expectFailure(label, "stale-array-descriptor-leaf",
			() -> OcamlRepresentationRegistry.validateRepresentedArrayDescriptor(cast corrupted, element, "program:representation-fixture"));
	}

	/** Registers the closed fixture class with its already-sealed Int field. */
	static function registerCounter(registry:OcamlRepresentationRegistry):Type {
		final counterType = Context.getType("RepresentationCounter");
		final field = registry.selectExactInt(OcamlRepresentationDomain.InstanceField);
		registry.registerMonomorphicClass({
			semanticTypeId: "RepresentationCounter",
			sourceModuleId: "RepresentationCounter",
			sourceTypeName: "RepresentationCounter",
			targetModuleName: "RepresentationCounter",
			targetTypeName: "representation_counter_t",
			fields: [
				{
					declarationOrder: 0,
					sourceFieldName: "value",
					targetFieldName: "value",
					semanticTypeId: field.semanticTypeId,
					carrierTypeId: field.carrierTypeId,
					representationId: field.id
				}
			]
		});
		return counterType;
	}

	/** Runs during compilation so exact built-in Haxe types are available. */
	public static function run():Void {
		final registry = new OcamlRepresentationRegistry();
		expectFailure("unstarted registry", "beginProgram", () -> registry.selectExactInt(OcamlRepresentationDomain.InternalValue));

		registry.beginProgram("program:representation-fixture");
		assertTrue(OcamlRepresentationRegistry.isExactInt(Context.typeof(macro(0 : Int))), "the built-in non-null Int should be admitted");
		assertTrue(!OcamlRepresentationRegistry.isExactInt(Context.typeof(macro(0.0 : Float))), "Float should remain outside the first slice");
		assertTrue(!OcamlRepresentationRegistry.isExactInt(Context.typeof(macro(null : Null<Int>))), "nullable Int should remain outside the first slice");
		assertTrue(OcamlRepresentationRegistry.isExactNullInt(Context.typeof(macro(null : Null<Int>))),
			"the direct core Null<Int> wrapper should be admitted by its dedicated predicate");
		assertTrue(!OcamlRepresentationRegistry.isExactNullInt(Context.typeof(macro(null : Null<Float>))),
			"Null<Float> should remain outside the exact Null<Int> slice");
		assertTrue(!OcamlRepresentationRegistry.isExactNullInt(Context.typeof(macro(null : Null<IntAlias>))),
			"Null<IntAlias> should need its own proof instead of following the typedef implicitly");
		assertTrue(OcamlRepresentationRegistry.isExactBool(Context.typeof(macro(false : Bool))),
			"the built-in non-null Bool should be available to exact nullable-Bool write planning");
		assertTrue(OcamlRepresentationRegistry.isExactNullBool(Context.typeof(macro(null : Null<Bool>))),
			"the direct core Null<Bool> wrapper should be admitted by its dedicated predicate");
		assertTrue(!OcamlRepresentationRegistry.isExactNullBool(Context.typeof(macro(null : Null<Int>))),
			"Null<Int> should remain outside the exact Null<Bool> slice");
		assertTrue(!OcamlRepresentationRegistry.isExactNullBool(Context.typeof(macro(null : Null<BoolAlias>))),
			"Null<BoolAlias> should need its own proof instead of following the typedef implicitly");
		assertTrue(OcamlRepresentationRegistry.isExactString(Context.typeof(macro("value" : String))),
			"the direct core String should be admitted by its dedicated predicate");
		assertTrue(OcamlRepresentationRegistry.isExactString(Context.typeof(macro(null : String))),
			"the direct core String predicate should not confuse its nullable value with a different semantic type");
		assertTrue(OcamlRepresentationRegistry.isExactNullString(Context.typeof(macro(null : Null<String>))),
			"the core Null<String> macro type should be recognized only for optional String boundary normalization");
		assertTrue(!OcamlRepresentationRegistry.isExactString(Context.typeof(macro("value" : StringAlias))),
			"a String typedef should need its own proof instead of following the typedef implicitly");
		assertTrue(!OcamlRepresentationRegistry.isExactString(Context.typeof(macro(0 : Int))), "Int should remain outside the exact String slice");
		assertTrue(OcamlRepresentationRegistry.isExactDynamic(Context.typeof(macro(null : Dynamic))),
			"the direct Dynamic type should be admitted by its dedicated predicate");
		assertTrue(!OcamlRepresentationRegistry.isExactDynamic(Context.typeof(macro("value" : String))),
			"a concrete value must remain visible to occurrence-bound Dynamic conversion planning");
		assertTrue(OcamlRepresentationRegistry.normalizedDirectFlatArray(Context.typeof(macro([] : Array<Int>))) != null,
			"the direct nominal Array<Int> should be admitted");
		assertTrue(OcamlRepresentationRegistry.normalizedDirectFlatArray(Context.typeof(macro([] : Array<Float>))) == null,
			"Array<Float> should remain outside the exact Array<Int> slice");
		assertTrue(OcamlRepresentationRegistry.normalizedDirectFlatArray(Context.typeof(macro([] : Array<String>))) == null,
			"the String literal proof must not implicitly admit Array<String> to general represented consumers");
		final stringLiteralCandidate = OcamlDirectArraySourceIdentity.normalize(Context.typeof(macro([] : Array<String>)));
		assertTrue(stringLiteralCandidate != null
			&& stringLiteralCandidate.arraySemanticTypeId == "Array<String>"
			&& stringLiteralCandidate.elementSemanticTypeId == "String",
			"the shared source parser should describe direct Array<String> without granting general carrier admission");
		assertTrue(OcamlDirectArraySourceIdentity.normalize(Context.typeof(macro([] : Array<Float>))) == null,
			"the source parser should reject element families without a proved literal contract");
		assertTrue(OcamlDirectArraySourceIdentity.normalize(Context.typeof(macro([] : IntArrayAlias))) == null,
			"the source parser should not follow an outer array typedef");
		assertTrue(OcamlDirectArraySourceIdentity.normalize(Context.typeof(macro([] : Array<IntAlias>))) == null,
			"the source parser should not follow an element typedef");
		assertTrue(OcamlRepresentationRegistry.normalizedDirectFlatArray(Context.typeof(macro(null : Null<Array<Int>>))) == null,
			"an explicit nullable Array<Int> wrapper should remain outside the slice");
		assertTrue(OcamlRepresentationRegistry.normalizedDirectFlatArray(Context.typeof(macro([] : IntArrayAlias))) == null,
			"an Array<Int> typedef should need its own representation proof instead of being followed implicitly");
		assertTrue(OcamlRepresentationRegistry.normalizedDirectFlatArray(Context.typeof(macro([] : Array<IntAlias>))) == null,
			"an Array whose element is an Int typedef should need its own representation proof instead of being followed implicitly");
		assertTrue(OcamlRepresentationRegistry.normalizedDirectFlatArray(Context.typeof(macro(new haxe.ds.Vector<Int>(1)))) == null,
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
		assertTrue(OcamlRepresentationRegistry.normalizedDirectFlatArray(genericArrayType) == null,
			"Array<T> should remain outside the exact Array<Int> representation proof");
		final directArrayIdentity = OcamlRepresentationRegistry.normalizedDirectFlatArray(Context.typeof(macro([] : Array<Int>)));
		assertTrue(directArrayIdentity != null
			&& directArrayIdentity.arraySemanticTypeId == "Array<Int>"
			&& directArrayIdentity.elementSemanticTypeId == "Int"
			&& directArrayIdentity.sourceForm == "direct-builtin-array"
			&& directArrayIdentity.closureKind == "closed-monomorphic"
			&& directArrayIdentity.outerWrapperKind == "none"
			&& directArrayIdentity.nestingKind == "flat",
			"the host adapter should normalize one direct closed flat Array<Int> without retaining the Haxe Type object");
		assertTrue(OcamlRepresentationRegistry.normalizedDirectFlatArray(Context.typeof(macro([] : Array<Float>))) == null,
			"an element family without an ArrayElement representation should not become a represented array identity");
		assertTrue(OcamlRepresentationRegistry.normalizedDirectFlatArray(Context.typeof(macro(null : Null<Array<Int>>))) == null,
			"an explicit nullable array wrapper should remain outside the direct flat identity");
		assertTrue(OcamlRepresentationRegistry.normalizedDirectFlatArray(genericArrayType) == null,
			"an open generic array should remain outside the closed represented-array identity");
		final dormantStringArrayIdentity:OcamlNormalizedRepresentedArray = {
			arraySemanticTypeId: "Array<String>",
			elementSemanticTypeId: "String",
			sourceForm: "direct-builtin-array",
			closureKind: "closed-monomorphic",
			outerWrapperKind: "none",
			nestingKind: "flat"
		};
		final mismatchedStringArrayIdentity:OcamlNormalizedRepresentedArray = {
			arraySemanticTypeId: "Array<Int>",
			elementSemanticTypeId: "String",
			sourceForm: "direct-builtin-array",
			closureKind: "closed-monomorphic",
			outerWrapperKind: "none",
			nestingKind: "flat"
		};
		expectFailure("mismatched String array identity", "invalid-array-shape",
			() -> registry.selectNormalizedRepresentedArray(mismatchedStringArrayIdentity, OcamlRepresentationDomain.InternalValue));
		final dormantStringArray = registry.selectNormalizedRepresentedArray(dormantStringArrayIdentity, OcamlRepresentationDomain.InternalValue);
		final dormantMutableStringArray = registry.selectNormalizedRepresentedArray(dormantStringArrayIdentity, OcamlRepresentationDomain.MutableLocalStorage);
		final dormantCapturedStringArray = registry.selectNormalizedRepresentedArray(dormantStringArrayIdentity,
			OcamlRepresentationDomain.CapturedLocalStorage);
		assertTrue(dormantStringArray.semanticTypeId == "Array<String>" && dormantStringArray.carrierTypeId == "string HxArray.t",
			"an explicit host-neutral Array<String> identity should compose its proven String element carrier without enabling host normalization");

		final mutable = registry.selectExactInt(OcamlRepresentationDomain.MutableLocalStorage);
		final internal = registry.selectExactInt(OcamlRepresentationDomain.InternalValue);
		final captured = registry.selectExactInt(OcamlRepresentationDomain.CapturedLocalStorage);
		final instanceField = registry.selectExactInt(OcamlRepresentationDomain.InstanceField);
		final staticField = registry.selectExactInt(OcamlRepresentationDomain.StaticField);
		final boolInternal = registry.selectExactBool(OcamlRepresentationDomain.InternalValue);
		final boolMutable = registry.selectExactBool(OcamlRepresentationDomain.MutableLocalStorage);
		final boolCaptured = registry.selectExactBool(OcamlRepresentationDomain.CapturedLocalStorage);
		final boolInstanceField = registry.selectExactBool(OcamlRepresentationDomain.InstanceField);
		final boolStaticField = registry.selectExactBool(OcamlRepresentationDomain.StaticField);
		final arrayInternal = registry.selectRepresentedArray(Context.typeof(macro([] : Array<Int>)), OcamlRepresentationDomain.InternalValue);
		final arrayMutable = registry.selectRepresentedArray(Context.typeof(macro([] : Array<Int>)), OcamlRepresentationDomain.MutableLocalStorage);
		final arrayCaptured = registry.selectRepresentedArray(Context.typeof(macro([] : Array<Int>)), OcamlRepresentationDomain.CapturedLocalStorage);
		assertTrue(arrayInternal != null && arrayMutable != null && arrayCaptured != null,
			"the registry should admit the existing Array<Int> local domains through the represented-array selector");
		final arrayDescriptor = registry.requireRepresentedArray(arrayInternal.arrayDescriptorId, arrayInternal.arrayDescriptorRevision,
			"program:representation-fixture");
		assertTrue(arrayDescriptor.arraySemanticTypeId == "Array<Int>"
			&& arrayDescriptor.elementSemanticTypeId == "Int"
			&& arrayDescriptor.elementDomain == OcamlRepresentationDomain.ArrayElement
			&& arrayDescriptor.elementCarrierTypeId == "int"
			&& arrayDescriptor.elementRepresentationId == "representation:Int:array-element"
			&& arrayDescriptor.arrayCarrierTypeId == "int HxArray.t"
			&& arrayDescriptor.carrierFamilyId == "HxArray"
			&& arrayDescriptor.runtimeCarrierCapabilityId == "haxe-array"
			&& arrayDescriptor.runtimeKindTagId == "Array",
			"the represented array should bind its exact ArrayElement decision and composed HxArray carrier once");
		assertTrue(arrayInternal.arrayDescriptorId == arrayDescriptor.id
			&& arrayInternal.arrayDescriptorRevision == arrayDescriptor.revision
			&& registry.require(arrayDescriptor.elementRepresentationId, "program:representation-fixture")
				.revision == arrayDescriptor.elementRepresentationRevision,
			"the array representation should retain exact descriptor and element-representation revisions");
		final dormantStringArrayDescriptor = registry.requireRepresentedArray(dormantStringArray.arrayDescriptorId,
			dormantStringArray.arrayDescriptorRevision, "program:representation-fixture");
		final dormantStringElement = registry.require(dormantStringArrayDescriptor.elementRepresentationId, "program:representation-fixture");
		assertTrue(dormantStringArrayDescriptor.arraySemanticTypeId == "Array<String>"
			&& dormantStringArrayDescriptor.elementSemanticTypeId == "String"
			&& dormantStringArrayDescriptor.elementDomain == OcamlRepresentationDomain.ArrayElement
			&& dormantStringArrayDescriptor.elementCarrierTypeId == "string"
			&& dormantStringArrayDescriptor.elementRepresentationId == "representation:String:array-element"
			&& dormantStringArrayDescriptor.elementRepresentationRevision == dormantStringElement.revision
			&& dormantStringArrayDescriptor.arrayCarrierTypeId == "string HxArray.t"
			&& dormantStringArrayDescriptor.carrierFamilyId == "HxArray"
			&& dormantStringArrayDescriptor.runtimeCarrierCapabilityId == "haxe-array"
			&& dormantStringArrayDescriptor.runtimeKindTagId == "Array"
			&& dormantStringArrayDescriptor.sourceForm == "direct-builtin-array"
			&& dormantStringArrayDescriptor.closureKind == "closed-monomorphic"
			&& dormantStringArrayDescriptor.outerWrapperKind == "none"
			&& dormantStringArrayDescriptor.nestingKind == "flat"
			&& dormantStringArrayDescriptor.proofId == "direct-flat-array-element-binding-v1"
			&& dormantStringArrayDescriptor.profileEligibility.join(",") == "metal,portable",
			"the dormant Array<String> descriptor should bind every shape and carrier fact to the exact String array-element decision");
		assertTrue(dormantStringArray.arrayDescriptorId == dormantStringArrayDescriptor.id
			&& dormantStringArray.arrayDescriptorRevision == dormantStringArrayDescriptor.revision
			&& dormantStringArray.nullPolicy == OcamlRepresentationNullPolicy.RuntimeSentinel
			&& dormantStringArray.identityPolicy == OcamlRepresentationIdentityPolicy.ReferenceIdentity
			&& dormantStringArray.aliasingPolicy == OcamlRepresentationAliasingPolicy.SharedReferenceAliases
			&& dormantStringArray.storageMutationPolicy == OcamlRepresentationStorageMutationPolicy.ImmutableBinding
			&& dormantMutableStringArray.storageMutationPolicy == OcamlRepresentationStorageMutationPolicy.SharedLocalCell
			&& dormantCapturedStringArray.storageMutationPolicy == OcamlRepresentationStorageMutationPolicy.SharedLocalCell
			&& dormantStringArray.valueMutationPolicy == OcamlRepresentationValueMutationPolicy.MutableRuntimeContainer
			&& dormantStringArray.boxingPolicy == OcamlRepresentationBoxingPolicy.DirectRuntimeContainer
			&& dormantStringArray.implicitDefaultPolicy == OcamlRepresentationImplicitDefaultPolicy.NotAdmitted
			&& dormantStringArray.proof.id == "direct-represented-array-reference-carrier-v1"
			&& dormantStringArray.profileEligibility.join(",") == "metal,portable",
			"the dormant Array<String> outer decisions should own reference identity, container mutation, and each local storage owner");
		OcamlRepresentationRegistry.validateDecisionSnapshot(dormantStringArray, "program:representation-fixture");
		OcamlRepresentationRegistry.validateDecisionSnapshot(dormantMutableStringArray, "program:representation-fixture");
		OcamlRepresentationRegistry.validateDecisionSnapshot(dormantCapturedStringArray, "program:representation-fixture");
		final nullableInternal = registry.selectExactNullInt(OcamlRepresentationDomain.InternalValue);
		final nullableMutable = registry.selectExactNullInt(OcamlRepresentationDomain.MutableLocalStorage);
		final nullableCaptured = registry.selectExactNullInt(OcamlRepresentationDomain.CapturedLocalStorage);
		final nullableInstanceField = registry.selectExactNullInt(OcamlRepresentationDomain.InstanceField);
		final nullableStaticField = registry.selectExactNullInt(OcamlRepresentationDomain.StaticField);
		final nullableBoolInternal = registry.selectExactNullBool(OcamlRepresentationDomain.InternalValue);
		final nullableBoolMutable = registry.selectExactNullBool(OcamlRepresentationDomain.MutableLocalStorage);
		final nullableBoolCaptured = registry.selectExactNullBool(OcamlRepresentationDomain.CapturedLocalStorage);
		final nullableBoolInstanceField = registry.selectExactNullBool(OcamlRepresentationDomain.InstanceField);
		final nullableBoolStaticField = registry.selectExactNullBool(OcamlRepresentationDomain.StaticField);
		final stringInternal = registry.selectExactString(OcamlRepresentationDomain.InternalValue);
		final stringMutable = registry.selectExactString(OcamlRepresentationDomain.MutableLocalStorage);
		final stringCaptured = registry.selectExactString(OcamlRepresentationDomain.CapturedLocalStorage);
		final stringInstanceField = registry.selectExactString(OcamlRepresentationDomain.InstanceField);
		final stringStaticField = registry.selectExactString(OcamlRepresentationDomain.StaticField);
		final stringArrayElement = registry.selectExactString(OcamlRepresentationDomain.ArrayElement);
		final dynamicInternal = registry.selectExactDynamic(OcamlRepresentationDomain.InternalValue);
		final counterType = registerCounter(registry);
		final counterInternal = registry.selectMonomorphicClassValue(counterType, OcamlRepresentationDomain.InternalValue);
		final counterCaptured = registry.selectMonomorphicClassValue(counterType, OcamlRepresentationDomain.CapturedLocalStorage);
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
		assertTrue(instanceField.implicitDefaultPolicy == OcamlRepresentationImplicitDefaultPolicy.ExactIntZero
			&& staticField.implicitDefaultPolicy == OcamlRepresentationImplicitDefaultPolicy.ExactIntZero,
			"exact Int fields should carry the same explicit Haxe zero-default policy");
		final instanceMaterialization = OcamlFieldRepresentationMaterializer.materializeExactInt(instanceField, OcamlRepresentationDomain.InstanceField);
		final carrierIsInt = switch (instanceMaterialization.carrierType) {
			case TIdent("int"): true;
			case _: false;
		}
		final defaultIsZero = switch (instanceMaterialization.implicitDefault) {
			case EConst(CInt(0)): true;
			case _: false;
		}
		assertTrue(carrierIsInt && defaultIsZero, "an exact Int instance field should materialize directly as OCaml int with a zero default");
		assertTrue(boolInternal.semanticTypeId == "Bool"
			&& boolInternal.carrierTypeId == "bool"
			&& boolInternal.nullPolicy == OcamlRepresentationNullPolicy.NonNull
			&& boolInternal.boxingPolicy == OcamlRepresentationBoxingPolicy.DirectUnboxed,
			"exact Bool locals should use the direct non-null OCaml bool carrier");
		assertTrue(boolInternal.implicitDefaultPolicy == OcamlRepresentationImplicitDefaultPolicy.ExactBoolFalse,
			"exact Bool decisions should record their semantic false default");
		assertTrue(boolInternal.proof.id == "direct-exact-bool-storage-v2"
			&& boolInternal.proof.claim.indexOf("does not admit nullable values, array elements, calls, operators, native boundaries, or public ABI") >= 0,
			"the exact Bool proof should state its bounded storage boundary");
		assertTrue(boolMutable.storageMutationPolicy == OcamlRepresentationStorageMutationPolicy.SharedLocalCell
			&& boolCaptured.storageMutationPolicy == OcamlRepresentationStorageMutationPolicy.SharedLocalCell
			&& boolInstanceField.storageMutationPolicy == OcamlRepresentationStorageMutationPolicy.InstanceFieldOwner
			&& boolStaticField.storageMutationPolicy == OcamlRepresentationStorageMutationPolicy.StaticFieldOwner,
			"exact Bool storage should name the local, instance, or static owner that performs replacement");
		final boolInstanceMaterialization = OcamlFieldRepresentationMaterializer.materializeDirectPrimitive(boolInstanceField,
			OcamlRepresentationDomain.InstanceField);
		final boolCarrierIsDirect = switch (boolInstanceMaterialization.carrierType) {
			case TIdent("bool"): true;
			case _: false;
		}
		final boolDefaultIsFalse = switch (boolInstanceMaterialization.implicitDefault) {
			case EConst(CBool(false)): true;
			case _: false;
		}
		assertTrue(boolCarrierIsDirect && boolDefaultIsFalse, "an exact Bool instance field should materialize directly as OCaml bool with a false default");
		assertTrue(arrayInternal.semanticTypeId == "Array<Int>" && arrayInternal.carrierTypeId == "int HxArray.t",
			"the direct Array<Int> internal value should use the typed HxArray carrier");
		assertTrue(arrayInternal.implicitDefaultPolicy == OcamlRepresentationImplicitDefaultPolicy.NotAdmitted,
			"the local Array<Int> carrier should not imply a field default");
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
		assertTrue(arrayInternal.proof.id == "direct-represented-array-reference-carrier-v1"
			&& arrayInternal.proof.claim.indexOf("does not admit another element family") >= 0,
			"the represented-array proof should name its narrow boundary instead of generalizing all arrays");
		assertTrue(nullableInternal.semanticTypeId == "Null<Int>"
			&& nullableInternal.carrierTypeId == "Obj.t"
			&& nullableInternal.nullPolicy == OcamlRepresentationNullPolicy.RuntimeSentinel
			&& nullableInternal.boxingPolicy == OcamlRepresentationBoxingPolicy.NullablePrimitiveCarrier,
			"exact Null<Int> locals should use the runtime-sentinel Obj.t carrier");
		assertTrue(nullableInternal.implicitDefaultPolicy == OcamlRepresentationImplicitDefaultPolicy.RuntimeNullSentinel,
			"the nullable-Int decision should record its runtime null sentinel");
		assertTrue(nullableInternal.proof.id == "nullable-int-obj-carrier-v2"
			&& nullableInternal.proof.claim.indexOf("field storage and implicit null defaults only") >= 0,
			"the nullable carrier proof should state its bounded field-storage boundary");
		assertTrue(nullableMutable.storageMutationPolicy == OcamlRepresentationStorageMutationPolicy.SharedLocalCell
			&& nullableCaptured.storageMutationPolicy == OcamlRepresentationStorageMutationPolicy.SharedLocalCell
			&& nullableInstanceField.storageMutationPolicy == OcamlRepresentationStorageMutationPolicy.InstanceFieldOwner
			&& nullableStaticField.storageMutationPolicy == OcamlRepresentationStorageMutationPolicy.StaticFieldOwner,
			"exact Null<Int> storage should retain distinct local, instance, and static owners");
		assertTrue(nullableBoolInternal.semanticTypeId == "Null<Bool>"
			&& nullableBoolInternal.carrierTypeId == "Obj.t"
			&& nullableBoolInternal.nullPolicy == OcamlRepresentationNullPolicy.RuntimeSentinel
			&& nullableBoolInternal.boxingPolicy == OcamlRepresentationBoxingPolicy.NullablePrimitiveCarrier,
			"exact Null<Bool> locals should preserve null, false, and true in the runtime-sentinel Obj.t carrier");
		assertTrue(nullableBoolInternal.implicitDefaultPolicy == OcamlRepresentationImplicitDefaultPolicy.RuntimeNullSentinel,
			"the nullable-Bool decision should record its runtime null sentinel");
		assertTrue(nullableBoolInternal.proof.id == "nullable-bool-obj-carrier-v2"
			&& nullableBoolInternal.proof.claim.indexOf("three distinct Haxe Null<Bool> values") >= 0,
			"the nullable-Bool proof should state its three-state storage boundary");
		assertTrue(nullableBoolMutable.storageMutationPolicy == OcamlRepresentationStorageMutationPolicy.SharedLocalCell
			&& nullableBoolCaptured.storageMutationPolicy == OcamlRepresentationStorageMutationPolicy.SharedLocalCell
			&& nullableBoolInstanceField.storageMutationPolicy == OcamlRepresentationStorageMutationPolicy.InstanceFieldOwner
			&& nullableBoolStaticField.storageMutationPolicy == OcamlRepresentationStorageMutationPolicy.StaticFieldOwner,
			"exact Null<Bool> storage should retain distinct local, instance, and static owners");
		assertTrue(stringInternal.semanticTypeId == "String"
			&& stringInternal.carrierTypeId == "string"
			&& stringInternal.nullPolicy == OcamlRepresentationNullPolicy.RuntimeSentinel
			&& stringInternal.boxingPolicy == OcamlRepresentationBoxingPolicy.NullableStringCarrier
			&& stringInternal.implicitDefaultPolicy == OcamlRepresentationImplicitDefaultPolicy.RuntimeNullSentinel,
			"exact String should preserve null and non-null text in the sealed string carrier");
		assertTrue(stringInternal.identityPolicy == OcamlRepresentationIdentityPolicy.PrimitiveValue
			&& stringInternal.aliasingPolicy == OcamlRepresentationAliasingPolicy.NoValueAlias
			&& stringInternal.valueMutationPolicy == OcamlRepresentationValueMutationPolicy.ImmutableValue
			&& stringMutable.storageMutationPolicy == OcamlRepresentationStorageMutationPolicy.SharedLocalCell
			&& stringCaptured.storageMutationPolicy == OcamlRepresentationStorageMutationPolicy.SharedLocalCell
			&& stringInstanceField.storageMutationPolicy == OcamlRepresentationStorageMutationPolicy.InstanceFieldOwner
			&& stringStaticField.storageMutationPolicy == OcamlRepresentationStorageMutationPolicy.StaticFieldOwner
			&& stringArrayElement.storageMutationPolicy == OcamlRepresentationStorageMutationPolicy.ArrayElementOwner,
			"exact String should separate immutable text values from the local, field, or array slot that replaces them");
		assertTrue(stringInternal.proof.id == "nullable-string-runtime-sentinel-carrier-v1"
			&& stringInternal.proof.claim.indexOf("single runtime-owned HxString.hx_null_string") >= 0,
			"the exact String proof should name and confine its runtime-null boundary");
		assertTrue(stringArrayElement.semanticTypeId == "String"
			&& stringArrayElement.carrierTypeId == "string"
			&& stringArrayElement.nullPolicy == OcamlRepresentationNullPolicy.RuntimeSentinel
			&& stringArrayElement.identityPolicy == OcamlRepresentationIdentityPolicy.PrimitiveValue
			&& stringArrayElement.aliasingPolicy == OcamlRepresentationAliasingPolicy.NoValueAlias
			&& stringArrayElement.valueMutationPolicy == OcamlRepresentationValueMutationPolicy.ImmutableValue
			&& stringArrayElement.boxingPolicy == OcamlRepresentationBoxingPolicy.NullableStringCarrier
			&& stringArrayElement.implicitDefaultPolicy == OcamlRepresentationImplicitDefaultPolicy.RuntimeNullSentinel
			&& stringArrayElement.proof.id == "nullable-string-array-element-carrier-v1"
			&& stringArrayElement.proof.claim.indexOf("sparse and out-of-bounds slots") >= 0,
			"the String array-element decision should preserve nullable values without exposing HxArray's private storage mode");
		OcamlRepresentationRegistry.validateDecisionSnapshot(stringArrayElement, "program:representation-fixture");
		assertTrue(dynamicInternal.semanticTypeId == "Dynamic"
			&& dynamicInternal.carrierTypeId == "Obj.t"
			&& dynamicInternal.nullPolicy == OcamlRepresentationNullPolicy.RuntimeSentinel
			&& dynamicInternal.identityPolicy == OcamlRepresentationIdentityPolicy.DynamicPayloadIdentity
			&& dynamicInternal.aliasingPolicy == OcamlRepresentationAliasingPolicy.DynamicPayloadAliases
			&& dynamicInternal.storageMutationPolicy == OcamlRepresentationStorageMutationPolicy.ImmutableBinding
			&& dynamicInternal.valueMutationPolicy == OcamlRepresentationValueMutationPolicy.DynamicPayloadMutation
			&& dynamicInternal.boxingPolicy == OcamlRepresentationBoxingPolicy.DynamicCarrier
			&& dynamicInternal.implicitDefaultPolicy == OcamlRepresentationImplicitDefaultPolicy.NotAdmitted,
			"Dynamic should use one immutable Obj.t binding while retaining the payload's identity, aliases, and mutation");
		assertTrue(dynamicInternal.proof.id == "dynamic-obj-carrier-v1" && dynamicInternal.proof.claim.indexOf("runtime's Bool box") >= 0,
			"the Dynamic proof should distinguish exact Bool from OCaml Int and bound the admitted lifecycle");
		assertTrue(counterInternal != null
			&& counterCaptured != null
			&& counterInternal.carrierTypeId == "representation_counter_t"
			&& counterInternal.storageMutationPolicy == OcamlRepresentationStorageMutationPolicy.ImmutableBinding
			&& counterCaptured.carrierTypeId == counterInternal.carrierTypeId
			&& counterCaptured.nominalLayoutRevision == counterInternal.nominalLayoutRevision
			&& counterCaptured.storageMutationPolicy == OcamlRepresentationStorageMutationPolicy.SharedLocalCell,
			"one nominal class carrier should serve both an immutable binding and its captured shared cell");
		final stringMaterialization = OcamlStringRepresentationMaterializer.materialize(stringInstanceField, OcamlRepresentationDomain.InstanceField);
		final stringCarrierIsDirect = switch (stringMaterialization.carrierType) {
			case TIdent("string"): true;
			case _: false;
		}
		final stringDefaultIsSentinel = switch (stringMaterialization.implicitDefault) {
			case EField(EIdent("HxString"), "hx_null_string"): true;
			case _: false;
		}
		assertTrue(stringCarrierIsDirect && stringDefaultIsSentinel,
			"an exact String field should materialize the direct carrier and its proof-backed Haxe null default");
		final nullableInstanceMaterialization = OcamlFieldRepresentationMaterializer.materializeRepresentedField(nullableInstanceField,
			OcamlRepresentationDomain.InstanceField);
		final nullableBoolStaticMaterialization = OcamlFieldRepresentationMaterializer.materializeRepresentedField(nullableBoolStaticField,
			OcamlRepresentationDomain.StaticField);
		final nullableCarrierIsObj = switch (nullableInstanceMaterialization.carrierType) {
			case TIdent("Obj.t"): true;
			case _: false;
		}
		final nullableBoolCarrierIsObj = switch (nullableBoolStaticMaterialization.carrierType) {
			case TIdent("Obj.t"): true;
			case _: false;
		}
		final nullableDefaultIsSentinel = switch (nullableInstanceMaterialization.implicitDefault) {
			case EField(EIdent("HxRuntime"), "hx_null"): true;
			case _: false;
		}
		final nullableBoolDefaultIsSentinel = switch (nullableBoolStaticMaterialization.implicitDefault) {
			case EField(EIdent("HxRuntime"), "hx_null"): true;
			case _: false;
		}
		assertTrue(nullableCarrierIsObj
			&& nullableBoolCarrierIsObj
			&& nullableDefaultIsSentinel
			&& nullableBoolDefaultIsSentinel
			&& nullableInstanceField.id != nullableBoolInstanceField.id,
			"nullable Int and Bool fields should share mechanical Obj.t/null syntax while retaining distinct semantic decisions");
		assertTrue(registry.require(mutable.id, "program:representation-fixture").revision == mutable.revision,
			"an exact-program lookup should return the selected decision");

		final repeated = registry.selectExactInt(OcamlRepresentationDomain.MutableLocalStorage);
		assertTrue(repeated.revision == mutable.revision && registry.decisions().length == 36 && registry.representedArrays().length == 2,
			"selecting the same answer twice should reuse one decision and both represented-array descriptors");
		final ordered = registry.decisions();
		assertTrue(ordered[0].id < ordered[1].id && ordered[1].id < ordered[2].id, "reported decisions should use deterministic identity order");

		mutable.profileEligibility.push("changed-by-caller");
		assertTrue(registry.require(mutable.id, "program:representation-fixture").profileEligibility.join(",") == "metal,portable",
			"mutating a returned profile list must not change the retained decision");
		expectFailure("wrong field domain", "wrong-domain",
			() -> OcamlFieldRepresentationMaterializer.materializeExactInt(mutable, OcamlRepresentationDomain.InstanceField));
		Reflect.setField(instanceField, "implicitDefaultPolicy", OcamlRepresentationImplicitDefaultPolicy.NotAdmitted);
		expectFailure("wrong field default", "unsupported-decision",
			() -> OcamlFieldRepresentationMaterializer.materializeExactInt(instanceField, OcamlRepresentationDomain.InstanceField));
		assertTrue(registry.require(instanceField.id, "program:representation-fixture")
			.implicitDefaultPolicy == OcamlRepresentationImplicitDefaultPolicy.ExactIntZero,
			"mutating a returned default policy must not change the retained decision");
		expectFailure("wrong Bool field domain", "wrong-domain",
			() -> OcamlFieldRepresentationMaterializer.materializeExactBool(boolMutable, OcamlRepresentationDomain.StaticField));
		Reflect.setField(boolInstanceField, "carrierTypeId", "int");
		expectFailure("wrong Bool field carrier", "unsupported-decision",
			() -> OcamlFieldRepresentationMaterializer.materializeExactBool(boolInstanceField, OcamlRepresentationDomain.InstanceField));
		assertTrue(registry.require(boolInstanceField.id, "program:representation-fixture").carrierTypeId == "bool",
			"mutating a returned Bool carrier must not change the retained decision");
		Reflect.setField(boolStaticField, "implicitDefaultPolicy", OcamlRepresentationImplicitDefaultPolicy.NotAdmitted);
		expectFailure("wrong Bool field default", "unsupported-decision",
			() -> OcamlFieldRepresentationMaterializer.materializeExactBool(boolStaticField, OcamlRepresentationDomain.StaticField));
		assertTrue(registry.require(boolStaticField.id, "program:representation-fixture")
			.implicitDefaultPolicy == OcamlRepresentationImplicitDefaultPolicy.ExactBoolFalse,
			"mutating a returned Bool default policy must not change the retained decision");
		final wrongBoolSemantic = registry.require(boolStaticField.id, "program:representation-fixture");
		Reflect.setField(wrongBoolSemantic, "semanticTypeId", "Float");
		expectFailure("wrong Bool semantic family", "unsupported-family",
			() -> OcamlFieldRepresentationMaterializer.materializeDirectPrimitive(wrongBoolSemantic, OcamlRepresentationDomain.StaticField));
		expectFailure("wrong nullable field domain", "wrong-domain",
			() -> OcamlFieldRepresentationMaterializer.materializeExactNullablePrimitive(nullableMutable, OcamlRepresentationDomain.InstanceField));
		Reflect.setField(nullableInstanceField, "carrierTypeId", "int");
		expectFailure("wrong nullable field carrier", "unsupported-decision",
			() -> OcamlFieldRepresentationMaterializer.materializeExactNullablePrimitive(nullableInstanceField, OcamlRepresentationDomain.InstanceField));
		assertTrue(registry.require(nullableInstanceField.id, "program:representation-fixture").carrierTypeId == "Obj.t",
			"mutating a returned nullable field carrier must not change the retained decision");
		Reflect.setField(nullableBoolStaticField, "implicitDefaultPolicy", OcamlRepresentationImplicitDefaultPolicy.NotAdmitted);
		expectFailure("wrong nullable field default", "unsupported-decision",
			() -> OcamlFieldRepresentationMaterializer.materializeExactNullablePrimitive(nullableBoolStaticField, OcamlRepresentationDomain.StaticField));
		expectFailure("wrong String field domain", "wrong-domain",
			() -> OcamlStringRepresentationMaterializer.materialize(stringMutable, OcamlRepresentationDomain.InstanceField));
		Reflect.setField(stringInstanceField, "carrierTypeId", "Obj.t");
		expectFailure("wrong String field carrier", "unsupported-decision",
			() -> OcamlStringRepresentationMaterializer.materialize(stringInstanceField, OcamlRepresentationDomain.InstanceField));
		assertTrue(registry.require(stringInstanceField.id, "program:representation-fixture").carrierTypeId == "string",
			"mutating a returned String carrier must not change the retained decision");
		final wrongStringProof = registry.require(stringStaticField.id, "program:representation-fixture");
		Reflect.setField(wrongStringProof.proof, "id", "unreviewed-string-cast");
		expectFailure("wrong String unsafe proof", "unsupported-decision",
			() -> OcamlStringRepresentationMaterializer.materialize(wrongStringProof, OcamlRepresentationDomain.StaticField));
		expectDecisionCorruption("missing String array null policy", stringArrayElement, "invalid-decision",
			decision -> Reflect.deleteField(decision, "nullPolicy"));
		expectDecisionCorruption("corrupted String array carrier", stringArrayElement, "stale-decision-snapshot",
			decision -> Reflect.setField(decision, "carrierTypeId", "Obj.t"));
		expectDecisionCorruption("corrupted String array storage owner", stringArrayElement, "stale-decision-snapshot",
			decision -> Reflect.setField(decision, "storageMutationPolicy", OcamlRepresentationStorageMutationPolicy.ImmutableBinding));
		expectDecisionCorruption("corrupted String array boxing", stringArrayElement, "stale-decision-snapshot",
			decision -> Reflect.setField(decision, "boxingPolicy", OcamlRepresentationBoxingPolicy.DirectUnboxed));
		expectDecisionCorruption("missing String array proof", stringArrayElement, "invalid-decision", decision -> {
			final proof:Dynamic = Reflect.field(decision, "proof");
			Reflect.deleteField(proof, "id");
		});
		expectDecisionCorruption("corrupted String array program", stringArrayElement, "stale-program-revision",
			decision -> Reflect.setField(decision, "programRevision", "program:other"));
		expectDecisionCorruption("corrupted String array revision", stringArrayElement, "stale-decision-snapshot",
			decision -> Reflect.setField(decision, "revision", "sha256:" + StringTools.lpad("", "3", 64)));
		expectArrayDescriptorCorruption("corrupted Array<String> element revision", dormantStringArrayDescriptor, dormantStringElement,
			descriptor -> Reflect.setField(descriptor, "elementRepresentationRevision", "sha256:" + StringTools.lpad("", "4", 64)));
		expectArrayDescriptorCorruption("corrupted Array<String> carrier", dormantStringArrayDescriptor, dormantStringElement,
			descriptor -> Reflect.setField(descriptor, "arrayCarrierTypeId", "Obj.t HxArray.t"));
		expectArrayDescriptorCorruption("corrupted Array<String> proof", dormantStringArrayDescriptor, dormantStringElement,
			descriptor -> Reflect.setField(descriptor, "proofId", "unreviewed-array-string-proof"));
		expectArrayDescriptorCorruption("corrupted Array<String> program", dormantStringArrayDescriptor, dormantStringElement,
			descriptor -> Reflect.setField(descriptor, "programRevision", "program:other"));
		expectArrayDescriptorCorruption("corrupted Array<String> profile", dormantStringArrayDescriptor, dormantStringElement,
			descriptor -> Reflect.setField(descriptor, "profileEligibility", ["portable"]));
		final corruptedStringElementCarrier:Dynamic = Reflect.copy(dormantStringElement);
		Reflect.setField(corruptedStringElementCarrier, "carrierTypeId", "Obj.t");
		expectFailure("corrupted Array<String> element carrier", "stale-array-descriptor-leaf",
			() -> OcamlRepresentationRegistry.validateRepresentedArrayDescriptor(dormantStringArrayDescriptor, cast corruptedStringElementCarrier,
				"program:representation-fixture"));
		final corruptedStringElementDomain:Dynamic = Reflect.copy(dormantStringElement);
		Reflect.setField(corruptedStringElementDomain, "domain", OcamlRepresentationDomain.InternalValue);
		expectFailure("corrupted Array<String> element domain", "stale-array-descriptor-leaf",
			() -> OcamlRepresentationRegistry.validateRepresentedArrayDescriptor(dormantStringArrayDescriptor, cast corruptedStringElementDomain,
				"program:representation-fixture"));
		expectDecisionCorruption("corrupted Array<String> outer carrier", dormantStringArray, "stale-decision-snapshot",
			decision -> Reflect.setField(decision, "carrierTypeId", "Obj.t HxArray.t"));
		expectDecisionCorruption("corrupted Array<String> outer proof", dormantStringArray, "stale-decision-snapshot", decision -> {
			final proof:Dynamic = Reflect.field(decision, "proof");
			Reflect.setField(proof, "id", "unreviewed-array-string-proof");
		});
		final staleStringArrayReference:Dynamic = Reflect.copy(dormantStringArray);
		Reflect.setField(staleStringArrayReference, "arrayDescriptorRevision", "sha256:" + StringTools.lpad("", "5", 64));
		expectFailure("corrupted Array<String> descriptor edge", "stale-array-descriptor", () -> registry.register(cast staleStringArrayReference));

		expectFailure("missing decision", "no representation decision exists",
			() -> registry.require("representation:Int:missing", "program:representation-fixture"));
		expectFailure("stale program", "registry belongs to", () -> registry.require(internal.id, "program:older"));
		expectFailure("stale represented-array program", "array descriptor",
			() -> registry.requireRepresentedArray(arrayDescriptor.id, arrayDescriptor.revision, "program:older"));
		expectFailure("stale represented-array revision", "stale-array-descriptor",
			() -> registry.requireRepresentedArray(arrayDescriptor.id, "sha256:" + StringTools.lpad("", "0", 64), "program:representation-fixture"));
		final corruptedArrayDescriptor:Dynamic = Reflect.copy(arrayDescriptor);
		Reflect.setField(corruptedArrayDescriptor, "elementRepresentationRevision", "sha256:" + StringTools.lpad("", "1", 64));
		expectFailure("corrupted represented-array element edge", "stale-array-descriptor-leaf",
			() -> OcamlRepresentationRegistry.validateRepresentedArrayDescriptor(cast corruptedArrayDescriptor,
				registry.require(arrayDescriptor.elementRepresentationId, "program:representation-fixture"), "program:representation-fixture"));
		final staleArrayReference:Dynamic = Reflect.copy(arrayInternal);
		Reflect.setField(staleArrayReference, "arrayDescriptorRevision", "sha256:" + StringTools.lpad("", "2", 64));
		expectFailure("corrupted array representation descriptor edge", "stale-array-descriptor", () -> registry.register(cast staleArrayReference));
		expectFailure("unsupported Array<Int> domain", "admitted only for internal, mutable-local, or captured-local storage",
			() -> registry.selectRepresentedArray(Context.typeof(macro([] : Array<Int>)), OcamlRepresentationDomain.InstanceField));
		expectFailure("unsupported Bool array domain", "admitted only for internal, local, instance-field, or static-field storage",
			() -> registry.selectExactBool(OcamlRepresentationDomain.ArrayElement));
		expectFailure("unsupported Null<Int> array domain", "admitted only for internal, local, instance-field, or static-field storage",
			() -> registry.selectExactNullInt(OcamlRepresentationDomain.ArrayElement));
		expectFailure("unsupported Null<Bool> array domain", "admitted only for internal, local, instance-field, or static-field storage",
			() -> registry.selectExactNullBool(OcamlRepresentationDomain.ArrayElement));
		expectFailure("unsupported Dynamic mutable domain", "Dynamic is admitted only as an internal value",
			() -> registry.selectExactDynamic(OcamlRepresentationDomain.MutableLocalStorage));
		expectFailure("unsupported mutable nominal class domain", "admitted only for immutable internal bindings or captured local cells",
			() -> registry.selectMonomorphicClassValue(counterType, OcamlRepresentationDomain.MutableLocalStorage));
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
			implicitDefaultPolicy: mutable.implicitDefaultPolicy,
			reason: mutable.reason,
			proof: mutable.proof,
			profileEligibility: mutable.profileEligibility
		}));

		final registryAgain = new OcamlRepresentationRegistry();
		registryAgain.beginProgram("program:representation-fixture");
		registryAgain.selectExactInt(OcamlRepresentationDomain.CapturedLocalStorage);
		registryAgain.selectExactInt(OcamlRepresentationDomain.InternalValue);
		registryAgain.selectExactInt(OcamlRepresentationDomain.MutableLocalStorage);
		registryAgain.selectExactInt(OcamlRepresentationDomain.InstanceField);
		registryAgain.selectExactInt(OcamlRepresentationDomain.StaticField);
		registryAgain.selectExactBool(OcamlRepresentationDomain.MutableLocalStorage);
		registryAgain.selectExactBool(OcamlRepresentationDomain.InternalValue);
		registryAgain.selectExactBool(OcamlRepresentationDomain.CapturedLocalStorage);
		registryAgain.selectExactBool(OcamlRepresentationDomain.InstanceField);
		registryAgain.selectExactBool(OcamlRepresentationDomain.StaticField);
		registryAgain.selectRepresentedArray(Context.typeof(macro([] : Array<Int>)), OcamlRepresentationDomain.InternalValue);
		registryAgain.selectRepresentedArray(Context.typeof(macro([] : Array<Int>)), OcamlRepresentationDomain.MutableLocalStorage);
		registryAgain.selectRepresentedArray(Context.typeof(macro([] : Array<Int>)), OcamlRepresentationDomain.CapturedLocalStorage);
		registryAgain.selectNormalizedRepresentedArray(dormantStringArrayIdentity, OcamlRepresentationDomain.InternalValue);
		registryAgain.selectNormalizedRepresentedArray(dormantStringArrayIdentity, OcamlRepresentationDomain.MutableLocalStorage);
		registryAgain.selectNormalizedRepresentedArray(dormantStringArrayIdentity, OcamlRepresentationDomain.CapturedLocalStorage);
		registryAgain.selectExactNullInt(OcamlRepresentationDomain.InternalValue);
		registryAgain.selectExactNullInt(OcamlRepresentationDomain.MutableLocalStorage);
		registryAgain.selectExactNullInt(OcamlRepresentationDomain.CapturedLocalStorage);
		registryAgain.selectExactNullInt(OcamlRepresentationDomain.InstanceField);
		registryAgain.selectExactNullInt(OcamlRepresentationDomain.StaticField);
		registryAgain.selectExactNullBool(OcamlRepresentationDomain.InternalValue);
		registryAgain.selectExactNullBool(OcamlRepresentationDomain.MutableLocalStorage);
		registryAgain.selectExactNullBool(OcamlRepresentationDomain.CapturedLocalStorage);
		registryAgain.selectExactNullBool(OcamlRepresentationDomain.InstanceField);
		registryAgain.selectExactNullBool(OcamlRepresentationDomain.StaticField);
		registryAgain.selectExactString(OcamlRepresentationDomain.InternalValue);
		registryAgain.selectExactString(OcamlRepresentationDomain.MutableLocalStorage);
		registryAgain.selectExactString(OcamlRepresentationDomain.CapturedLocalStorage);
		registryAgain.selectExactString(OcamlRepresentationDomain.InstanceField);
		registryAgain.selectExactString(OcamlRepresentationDomain.StaticField);
		registryAgain.selectExactString(OcamlRepresentationDomain.ArrayElement);
		registryAgain.selectExactDynamic(OcamlRepresentationDomain.InternalValue);
		final counterTypeAgain = registerCounter(registryAgain);
		registryAgain.selectMonomorphicClassValue(counterTypeAgain, OcamlRepresentationDomain.CapturedLocalStorage);
		assertTrue(registryAgain.revision() == registry.revision(), "registration order should not change the registry revision");

		registry.beginProgram("program:new-request");
		expectFailure("request reset", "no representation decision exists", () -> registry.require(internal.id, "program:new-request"));
		Sys.println("REFLAXE_OCAML_REPRESENTATION_REGISTRY_FIXTURE:PASS");
	}
}
#end
