#if macro
import haxe.macro.Context;
import haxe.macro.Type;
import reflaxe.ocaml.ast.OcamlConst;
import reflaxe.ocaml.ast.OcamlExpr;
import reflaxe.ocaml.lowered.OcamlLoweredOrigin.OcamlLoweredSourceSpan;
import reflaxe.ocaml.lowered.OcamlUnrepresentedFieldDefaultPlan;
import reflaxe.ocaml.lowered.OcamlUnrepresentedFieldDefaultPlan.OcamlUnrepresentedFieldDefaultKind;
import reflaxe.ocaml.runtimegen.OcamlRuntimeUseAuthority;

/** Checks the owner-bound fallback used by field types without a full representation decision. */
class UnrepresentedFieldDefaultFixture {
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

	/** Proves that one reference-like Haxe type receives one checked null default. */
	static function proveCastNullDefault(type:Type, ownerId:String, source:OcamlLoweredSourceSpan):Void {
		final plan = OcamlUnrepresentedFieldDefaultPlan.seal(type, ownerId, "program:fixture", source);
		final authority = new OcamlRuntimeUseAuthority(plan.revision, "portable", plan.runtimeRequirements, plan.runtimeUseOccurrences);
		final materialized = OcamlUnrepresentedFieldDefaultPlan.materialize(plan, type, authority);
		authority.reconcileExpression(materialized);
		assertTrue(plan.kind == OcamlUnrepresentedFieldDefaultKind.CastRuntimeNull
			&& plan.runtimeRequirements.length == 1
			&& plan.runtimeUseOccurrences.length == 1
			&& switch (materialized) {
				case EApp(EIdent("Obj.magic"), [ERuntimeIdent(reference)]): reference.exactSymbol == "HxRuntime.hx_null";
				case _: false;
			}, '$ownerId should own one checked null-sentinel default');
	}

	public static function run():Void {
		final source:OcamlLoweredSourceSpan = {file: "UnrepresentedFieldDefaultFixture.hx", min: 10, max: 20};
		final intPlan = OcamlUnrepresentedFieldDefaultPlan.seal(Context.typeof(macro(0 : Int)), "fixture:field:int", "program:fixture", source);
		assertTrue(intPlan.kind == OcamlUnrepresentedFieldDefaultKind.IntZero
			&& intPlan.runtimeRequirements.length == 0
			&& intPlan.runtimeUseOccurrences.length == 0
			&& switch (OcamlUnrepresentedFieldDefaultPlan.materialize(intPlan, Context.typeof(macro(0 : Int)), null)) {
				case EConst(CInt(0)): true;
				case _: false;
			}, "a direct Int default should produce zero without a private runtime value");

		final floatPlan = OcamlUnrepresentedFieldDefaultPlan.seal(Context.typeof(macro(0.0 : Float)), "fixture:field:float", "program:fixture", source);
		assertTrue(floatPlan.kind == OcamlUnrepresentedFieldDefaultKind.FloatZero
			&& floatPlan.runtimeRequirements.length == 0
			&& floatPlan.runtimeUseOccurrences.length == 0,
			"a direct Float default should need no private runtime value");
		assertTrue(switch (OcamlUnrepresentedFieldDefaultPlan.materialize(floatPlan, Context.typeof(macro(0.0 : Float)), null)) {
			case EConst(CFloat("0.")): true;
			case _: false;
		}, "the Float decision should materialize the existing direct zero default");
		final boolPlan = OcamlUnrepresentedFieldDefaultPlan.seal(Context.typeof(macro(false : Bool)), "fixture:field:bool", "program:fixture", source);
		assertTrue(boolPlan.kind == OcamlUnrepresentedFieldDefaultKind.BoolFalse
			&& boolPlan.runtimeRequirements.length == 0
			&& boolPlan.runtimeUseOccurrences.length == 0
			&& switch (OcamlUnrepresentedFieldDefaultPlan.materialize(boolPlan, Context.typeof(macro(false : Bool)), null)) {
				case EConst(CBool(false)): true;
				case _: false;
			}, "a direct Bool default should produce false without a private runtime value");

		final nullableFloatType = Context.typeof(macro(null : Null<Float>));
		final nullableFloatPlan = OcamlUnrepresentedFieldDefaultPlan.seal(nullableFloatType, "fixture:field:nullable-float", "program:fixture", source);
		final nullableFloatAuthority = new OcamlRuntimeUseAuthority(nullableFloatPlan.revision, "portable", nullableFloatPlan.runtimeRequirements,
			nullableFloatPlan.runtimeUseOccurrences);
		final nullableFloat = OcamlUnrepresentedFieldDefaultPlan.materialize(nullableFloatPlan, nullableFloatType, nullableFloatAuthority);
		nullableFloatAuthority.reconcileExpression(nullableFloat);
		assertTrue(nullableFloatPlan.kind == OcamlUnrepresentedFieldDefaultKind.RuntimeNull
			&& nullableFloatPlan.runtimeRequirements.length == 1
			&& nullableFloatPlan.runtimeRequirements[0].rootModules.join(",") == "HxRuntime"
			&& nullableFloatPlan.runtimeUseOccurrences.length == 1
			&& switch (nullableFloat) {
				case ERuntimeIdent(reference): reference.exactSymbol == "HxRuntime.hx_null";
				case _: false;
			}, "a nullable primitive fallback should own one direct null-sentinel occurrence");

		final dynamicType = Context.typeof(macro(null : Dynamic));
		final dynamicPlan = OcamlUnrepresentedFieldDefaultPlan.seal(dynamicType, "fixture:field:dynamic", "program:fixture", source);
		final dynamicAuthority = new OcamlRuntimeUseAuthority(dynamicPlan.revision, "portable", dynamicPlan.runtimeRequirements,
			dynamicPlan.runtimeUseOccurrences);
		final dynamicDefault = OcamlUnrepresentedFieldDefaultPlan.materialize(dynamicPlan, dynamicType, dynamicAuthority);
		dynamicAuthority.reconcileExpression(dynamicDefault);
		assertTrue(dynamicPlan.kind == OcamlUnrepresentedFieldDefaultKind.CastRuntimeNull && switch (dynamicDefault) {
			case EApp(EIdent("Obj.magic"), [ERuntimeIdent(reference)]): reference.exactSymbol == "HxRuntime.hx_null";
			case _: false;
		},
			"an opaque fallback should retain the existing Obj.magic-wrapped null sentinel");
		proveCastNullDefault(Context.typeof(macro(null : StringBuf)), "fixture:field:class", source);
		proveCastNullDefault(Context.typeof(macro(null : haxe.ds.Option<Int>)), "fixture:field:enum", source);

		expectFailure("missing default plan", "missing-plan", () -> OcamlUnrepresentedFieldDefaultPlan.materialize(cast null, dynamicType, dynamicAuthority));
		final staleRevision:Dynamic = Reflect.copy(dynamicPlan);
		Reflect.setField(staleRevision, "revision", "sha256:" + StringTools.lpad("", "0", 64));
		expectFailure("stale default revision", "stale-plan",
			() -> OcamlUnrepresentedFieldDefaultPlan.materialize(cast staleRevision, dynamicType,
				new OcamlRuntimeUseAuthority(dynamicPlan.revision, "portable", dynamicPlan.runtimeRequirements, dynamicPlan.runtimeUseOccurrences)));

		final staleKind:Dynamic = Reflect.copy(dynamicPlan);
		Reflect.setField(staleKind, "kind", OcamlUnrepresentedFieldDefaultKind.RuntimeNull);
		expectFailure("changed default kind", "stale-plan",
			() -> OcamlUnrepresentedFieldDefaultPlan.materialize(cast staleKind, dynamicType,
				new OcamlRuntimeUseAuthority(dynamicPlan.revision, "portable", dynamicPlan.runtimeRequirements, dynamicPlan.runtimeUseOccurrences)));

		final wrongOwner:Dynamic = Reflect.copy(dynamicPlan);
		Reflect.setField(wrongOwner, "ownerId", "fixture:field:other");
		expectFailure("changed field owner", "stale-plan",
			() -> OcamlUnrepresentedFieldDefaultPlan.materialize(cast wrongOwner, dynamicType,
				new OcamlRuntimeUseAuthority(dynamicPlan.revision, "portable", dynamicPlan.runtimeRequirements, dynamicPlan.runtimeUseOccurrences)));

		final wrongSymbol:Dynamic = Reflect.copy(dynamicPlan);
		final wrongUses = dynamicPlan.runtimeUseOccurrences.map(use -> Reflect.copy(use));
		Reflect.setField(wrongUses[0], "exactSymbol", "HxRuntime.is_null");
		Reflect.setField(wrongSymbol, "runtimeUseOccurrences", wrongUses);
		expectFailure("changed runtime symbol", "stale-plan",
			() -> OcamlUnrepresentedFieldDefaultPlan.materialize(cast wrongSymbol, dynamicType,
				new OcamlRuntimeUseAuthority(dynamicPlan.revision, "portable", dynamicPlan.runtimeRequirements, dynamicPlan.runtimeUseOccurrences)));

		expectFailure("missing runtime authority", "missing-runtime-authority",
			() -> OcamlUnrepresentedFieldDefaultPlan.materialize(dynamicPlan, dynamicType, null));
		expectFailure("missing runtime requirement", "has no exact requirement",
			() -> OcamlUnrepresentedFieldDefaultPlan.materialize(dynamicPlan, dynamicType,
				new OcamlRuntimeUseAuthority(dynamicPlan.revision, "portable", [], dynamicPlan.runtimeUseOccurrences)));
		expectFailure("wrong profile", "not eligible",
			() -> OcamlUnrepresentedFieldDefaultPlan.materialize(dynamicPlan, dynamicType,
				new OcamlRuntimeUseAuthority(dynamicPlan.revision, "unsupported", dynamicPlan.runtimeRequirements, dynamicPlan.runtimeUseOccurrences)));

		final duplicateAuthority = new OcamlRuntimeUseAuthority(dynamicPlan.revision, "portable", dynamicPlan.runtimeRequirements,
			dynamicPlan.runtimeUseOccurrences);
		OcamlUnrepresentedFieldDefaultPlan.materialize(dynamicPlan, dynamicType, duplicateAuthority);
		expectFailure("duplicate null default", "constructed more than once",
			() -> OcamlUnrepresentedFieldDefaultPlan.materialize(dynamicPlan, dynamicType, duplicateAuthority));

		final plainAuthority = new OcamlRuntimeUseAuthority(dynamicPlan.revision, "portable", dynamicPlan.runtimeRequirements,
			dynamicPlan.runtimeUseOccurrences);
		expectFailure("plain null default", "plain private runtime reference",
			() -> plainAuthority.reconcileExpression(OcamlExpr.EField(OcamlExpr.EIdent("HxRuntime"), "hx_null")));
	}
}
#end
