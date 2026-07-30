package reflaxe.ocaml.lowered;

#if (macro || reflaxe_runtime)
import haxe.macro.Type;
import haxe.macro.Type.TypedExpr;
import haxe.macro.TypeTools;

/** Stable identities for one ordinary Haxe enum before it enters `Dynamic`. */
typedef OcamlEnumDynamicCarrierIdentity = {
	/** Fully qualified Haxe enum name used by `HxEnum` at runtime. */
	final semanticTypeId:String;

	/**
		Target-neutral name for the native OCaml variant value.

		This is evidence about the carrier family, not rendered OCaml syntax.
		Final planning validates this identity before sealing the function. The
		syntax builder then uses the final typed node only as the value to emit and
		applies the already-sealed enum name; it does not decide the enum identity
		a second time.
	**/
	final carrierTypeId:String;
}

/**
	Defines the bounded enum-to-`Dynamic` carrier contract shared by planning,
	runtime ownership, and syntax validation.

	An ordinary Haxe enum is emitted as a native OCaml variant. Before that value
	can enter `Dynamic`'s `Obj.t` carrier, `HxEnum.box_if_needed` must attach the
	fully qualified Haxe enum name. Constant constructors then reuse one stable
	Dynamic box, while payload constructors remain distinct values. Native
	interop enums in the `ocaml` package are deliberately excluded because they
	do not use the Haxe enum runtime contract.
**/
class OcamlEnumDynamicCarrier {
	public static inline final CARRIER_MODEL = "haxe-enum-native-variant-carrier-v1";
	public static inline final DYNAMIC_CARRIER = "Obj.t";
	public static inline final RUNTIME_MODULE = "HxEnum";
	public static inline final RUNTIME_OPERATION = "box_if_needed";
	public static inline final RUNTIME_CAPABILITY = "haxe-enum-dynamic-box";
	public static inline final RUNTIME_FEATURE = "haxe-enum-dynamic-box-v1";

	/**
		Returns the sealed enum identity only for a constructor written at this
		exact expression.

		The first supported boundary is intentionally narrower than "any
		expression whose result type is an enum." `Choice.A` and
		`Choice.WithPayload(7)` are accepted because their constructor identity is
		visible in the final typed tree. A local read, function result, parameter,
		or field access returns null even when its static type is the same enum;
		those values need their own data-flow and call-boundary proof before they
		can safely skip the legacy path.
	**/
	public static function fromDirectValue(expression:TypedExpr):Null<OcamlEnumDynamicCarrierIdentity> {
		final unwrapped = unwrapTransparent(expression);
		final constructorEnum = switch (unwrapped.expr) {
			case TField(_, FEnum(enumRef, _)):
				enumRef.get();
			case TCall(callee, _):
				switch (unwrapTransparent(callee).expr) {
					case TField(_, FEnum(enumRef, _)): enumRef.get();
					case _: null;
				}
			case _:
				null;
		}
		if (constructorEnum == null)
			return null;
		final identity = fromType(unwrapped.t);
		if (identity == null)
			return null;
		final constructorSemanticTypeId = (constructorEnum.pack ?? []).concat([constructorEnum.name]).join(".");
		return identity.semanticTypeId == constructorSemanticTypeId ? identity : null;
	}

	/** Returns the sealed identity for one exact ordinary Haxe enum type. */
	public static function fromType(type:Type):Null<OcamlEnumDynamicCarrierIdentity> {
		return switch (TypeTools.follow(type)) {
			case TEnum(enumRef, _):
				final enumType = enumRef.get();
				final pack = enumType.pack ?? [];
				if (pack.length > 0 && pack[0] == "ocaml") {
					null;
				} else {
					final semanticTypeId = pack.concat([enumType.name]).join(".");
					{
						semanticTypeId: semanticTypeId,
						carrierTypeId: CARRIER_MODEL + ":" + semanticTypeId
					};
				}
			case _:
				null;
		}
	}

	/**
		Checks that retained identities still describe the same enum carrier.

		This validation prevents a stale or tampered plan from asking syntax to
		box one enum value under another enum's runtime name.
	**/
	public static function requireIdentity(semanticTypeId:String, carrierTypeId:String):Void {
		if (semanticTypeId.length == 0 || carrierTypeId != CARRIER_MODEL + ":" + semanticTypeId) {
			throw 'reflaxe.ocaml [ocaml-enum:wrong-dynamic-carrier]: expected $CARRIER_MODEL:$semanticTypeId, got "$carrierTypeId"';
		}
	}

	/** Returns the requirement identity owned by one sealed local conversion. */
	public static function runtimeRequirementId(conversionId:String):String {
		return conversionId + ":runtime:" + RUNTIME_CAPABILITY;
	}

	/** Removes typed wrappers that do not change which constructor is called. */
	static function unwrapTransparent(expression:TypedExpr):TypedExpr {
		return switch (expression.expr) {
			case TMeta(_, child), TParenthesis(child): unwrapTransparent(child);
			case _: expression;
		}
	}
}
#end
