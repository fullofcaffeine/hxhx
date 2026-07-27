#if macro
import haxe.macro.Context;
import haxe.macro.Type;
import reflaxe.ocaml.ast.OcamlConst;
import reflaxe.ocaml.ast.OcamlExpr;
import reflaxe.ocaml.ast.OcamlTypeExpr;
import reflaxe.ocaml.lowered.OcamlFieldRepresentationMaterializer;
import reflaxe.ocaml.lowered.OcamlRepresentationModel.OcamlRepresentationAliasingPolicy;
import reflaxe.ocaml.lowered.OcamlRepresentationModel.OcamlRepresentationBoxingPolicy;
import reflaxe.ocaml.lowered.OcamlRepresentationModel.OcamlRepresentationDomain;
import reflaxe.ocaml.lowered.OcamlRepresentationModel.OcamlRepresentationIdentityPolicy;
import reflaxe.ocaml.lowered.OcamlRepresentationModel.OcamlRepresentationImplicitDefaultPolicy;
import reflaxe.ocaml.lowered.OcamlRepresentationModel.OcamlRepresentationNullPolicy;
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
		final instanceField = registry.selectExactInt(OcamlRepresentationDomain.InstanceField);
		final staticField = registry.selectExactInt(OcamlRepresentationDomain.StaticField);
		final boolInternal = registry.selectExactBool(OcamlRepresentationDomain.InternalValue);
		final boolMutable = registry.selectExactBool(OcamlRepresentationDomain.MutableLocalStorage);
		final boolCaptured = registry.selectExactBool(OcamlRepresentationDomain.CapturedLocalStorage);
		final boolInstanceField = registry.selectExactBool(OcamlRepresentationDomain.InstanceField);
		final boolStaticField = registry.selectExactBool(OcamlRepresentationDomain.StaticField);
		final arrayInternal = registry.selectExactArrayInt(OcamlRepresentationDomain.InternalValue);
		final arrayMutable = registry.selectExactArrayInt(OcamlRepresentationDomain.MutableLocalStorage);
		final arrayCaptured = registry.selectExactArrayInt(OcamlRepresentationDomain.CapturedLocalStorage);
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
		assertTrue(arrayInternal.proof.id == "direct-array-int-reference-carrier-v2"
			&& arrayInternal.proof.claim.indexOf("does not admit generic") >= 0,
			"the Array<Int> proof should name its narrow boundary instead of generalizing all arrays");
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
			&& stringStaticField.storageMutationPolicy == OcamlRepresentationStorageMutationPolicy.StaticFieldOwner,
			"exact String should separate immutable text values from the local, instance, or static storage that replaces them");
		assertTrue(stringInternal.proof.id == "nullable-string-runtime-sentinel-carrier-v1"
			&& stringInternal.proof.claim.indexOf("single runtime-owned HxString.hx_null_string") >= 0,
			"the exact String proof should name and confine its runtime-null boundary");
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
		assertTrue(repeated.revision == mutable.revision
			&& registry.decisions().length == 28, "selecting the same answer twice should reuse one decision");
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

		expectFailure("missing decision", "no representation decision exists",
			() -> registry.require("representation:Int:missing", "program:representation-fixture"));
		expectFailure("stale program", "registry belongs to", () -> registry.require(internal.id, "program:older"));
		expectFailure("unsupported Array<Int> domain", "admitted only for internal, mutable-local, or captured-local storage",
			() -> registry.selectExactArrayInt(OcamlRepresentationDomain.InstanceField));
		expectFailure("unsupported Bool array domain", "admitted only for internal, local, instance-field, or static-field storage",
			() -> registry.selectExactBool(OcamlRepresentationDomain.ArrayElement));
		expectFailure("unsupported Null<Int> array domain", "admitted only for internal, local, instance-field, or static-field storage",
			() -> registry.selectExactNullInt(OcamlRepresentationDomain.ArrayElement));
		expectFailure("unsupported Null<Bool> array domain", "admitted only for internal, local, instance-field, or static-field storage",
			() -> registry.selectExactNullBool(OcamlRepresentationDomain.ArrayElement));
		expectFailure("unsupported String array domain", "admitted only for internal, local, instance-field, or static-field storage",
			() -> registry.selectExactString(OcamlRepresentationDomain.ArrayElement));
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
		registryAgain.selectExactArrayInt(OcamlRepresentationDomain.InternalValue);
		registryAgain.selectExactArrayInt(OcamlRepresentationDomain.MutableLocalStorage);
		registryAgain.selectExactArrayInt(OcamlRepresentationDomain.CapturedLocalStorage);
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
		assertTrue(registryAgain.revision() == registry.revision(), "registration order should not change the registry revision");

		registry.beginProgram("program:new-request");
		expectFailure("request reset", "no representation decision exists", () -> registry.require(internal.id, "program:new-request"));
		Sys.println("REFLAXE_OCAML_REPRESENTATION_REGISTRY_FIXTURE:PASS");
	}
}
#end
