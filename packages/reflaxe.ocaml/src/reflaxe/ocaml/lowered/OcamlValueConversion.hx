package reflaxe.ocaml.lowered;

#if macro
import haxe.macro.Type;
import haxe.macro.TypeTools;
import reflaxe.ocaml.lowered.OcamlDynamicEqualityPlan.OcamlDynamicCarrierModel;

/** The native OCaml value that a primitive carrier holds. */
enum abstract OcamlPrimitiveCarrier(String) to String {
	var IntCarrier = "int";
	var FloatCarrier = "float";
	var BoolCarrier = "bool";
}

/**
	How `reflaxe.ocaml` stores a value of one Haxe type.

	Two carriers can share one OCaml type. For example, `Null<Bool>` and `Dynamic`
	are both `Obj.t`, but `Null<Bool>` holds a plain OCaml `bool`, and `Dynamic`
	holds a tagged Boolean. A value that moves between two different carriers
	needs a conversion, even when OCaml accepts the value unchanged.
**/
enum OcamlValueCarrier {
	/** A native OCaml `int`, `float`, or `bool`. `haxe.Int32` uses the `int` carrier. */
	NativePrimitive(kind:OcamlPrimitiveCarrier);

	/** `Null<Int>`, `Null<Float>`, or `Null<Bool>`: an `Obj.t` that holds the native value or `HxRuntime.hx_null`. */
	NullablePrimitive(kind:OcamlPrimitiveCarrier);

	/** A Haxe enum value as its native OCaml variant. */
	NativeEnum(semanticTypeId:String);

	/** `Null<E>` for an enum `E`: an `Obj.t` that holds the native variant or `HxRuntime.hx_null`. */
	NullableEnum(semanticTypeId:String);

	/** `Dynamic`, `Any`, or an anonymous structure stored in `HxAnon`: the general-purpose `Obj.t`. */
	DynamicObj;

	/** A class instance, a string, or an array-backed abstract, nullable or not. */
	ObjectReference;

	/**
		A value of a type parameter: an `Obj.t` that holds the boxed value. Generic
		code writes `Bool` with `HxRuntime.box_bool` and other values with `Obj.repr`.
	**/
	TypeParameterValue;

	/** A function value. */
	FunctionValue;

	/** A type that this model does not classify yet. */
	UnclassifiedCarrier;
}

/** What a value needs when it moves from one carrier to another. */
enum OcamlValueConversionKind {
	/** The two carriers are the same. */
	SameCarrier;

	/** Put a native value into a nullable `Obj.t` carrier with `Obj.repr`. */
	BoxNullable;

	/** Convert an `Int` to `Float`, then put it into a `Null<Float>` carrier. */
	BoxIntAsNullableFloat;

	/** Read the native value of a nullable primitive. `hx_null` gives the type's default value, as on static targets. */
	UnboxNullablePrimitive(kind:OcamlPrimitiveCarrier);

	/** Read the value that an `Obj.t` carrier holds, with `Obj.obj`. */
	UnboxObj;

	/**
		Give a `Null<Bool>` value the tagged Boolean form of `Dynamic`. `hx_null`
		stays `hx_null`. Without the tag, `true` is the same immediate as the
		integer `1`, and a `Dynamic` reader prints or tests it as an `Int`.
	**/
	TagNullableBool;

	/**
		Read a `Null<Bool>` out of `Dynamic`. A Dynamic Boolean carries the tag from
		`TagNullableBool` or `HxRuntime.box_bool`; `Null<Bool>` stores a plain `bool`.
		`hx_null` stays `hx_null`.
	**/
	UntagNullableBool;

	/**
		Read a Haxe enum value out of `Dynamic`. A Dynamic enum is boxed with its enum
		name (`HxEnum.box_if_needed`), so it needs `HxEnum.unbox_or_obj`, not `Obj.obj`.
	**/
	UnboxDynamicEnum(semanticTypeId:String);
}

/**
	Decides the conversion for a value that moves from one Haxe type to another.

	Why: the bug `haxe_ocaml-9cqxj` showed that `reflaxe.ocaml` decided conversions
	separately at each kind of boundary, with different tables. A pair that one
	table did not list compiled to the value unchanged. For example, the cast in
	`(Green : Null<Color>)` kept the native variant where `Obj.t` was required,
	and the OCaml build failed.

	What: `carrierOf` classifies a type, and `decide` returns the conversion for
	one pair of types from one table. The unchecked-cast lowering and the
	nullable branches of the assignment conversion use this table.

	Limits: `decide` returns `null` for a pair that it does not list. The callers
	then keep their previous behavior. Later steps of `haxe_ocaml-9cqxj` add the
	remaining boundaries and pairs, and then make an unlisted pair with different
	carriers a compile error.
**/
class OcamlValueConversion {
	/** Returns the carrier of a value of `type`. */
	public static function carrierOf(type:Type):OcamlValueCarrier {
		final followed = OcamlDynamicCarrierModel.followNoAbstracts(type);
		switch (followed) {
			case TAbstract(abstractRef, [inner]) if (isCoreNull(abstractRef.get())):
				final primitive = primitiveOf(inner);
				if (primitive != null)
					return NullablePrimitive(primitive);
				final enumId = enumIdOf(TypeTools.follow(inner));
				if (enumId != null)
					return NullableEnum(enumId);
			case _:
				final primitive = primitiveOf(type);
				if (primitive != null)
					return NativePrimitive(primitive);
				final enumId = enumIdOf(followed);
				if (enumId != null)
					return NativeEnum(enumId);
		}
		if (OcamlDynamicCarrierModel.usesDynamicCarrier(type))
			return DynamicObj;
		return switch (OcamlDynamicCarrierModel.followNoAbstracts(OcamlDynamicCarrierModel.unwrapNullType(followed))) {
			case TInst(classRef, _) if (classRef.get().kind.match(KTypeParameter(_))):
				TypeParameterValue;
			case TInst(_, _):
				ObjectReference;
			case TFun(_, _):
				FunctionValue;
			case abstractType = TAbstract(_, _) if (OcamlArrayCastCarrier.isArrayBackedAbstract(abstractType)):
				ObjectReference;
			case _:
				UnclassifiedCarrier;
		}
	}

	/**
		Returns the conversion for a read of a field whose declared type is a type
		parameter, at the concrete type `actual`, such as `Holder<Int>.value`.
		Returns `null` when the declared type is not a type parameter.
	**/
	public static function decideGenericRead(declared:Type, actual:Type):Null<OcamlValueConversionKind> {
		return carrierOf(declared) == TypeParameterValue ? between(TypeParameterValue, carrierOf(actual)) : null;
	}

	/** Returns the conversion from a value of type `from` to type `to`, or `null` for a pair that the table does not list. */
	public static function decide(from:Type, to:Type):Null<OcamlValueConversionKind> {
		return between(carrierOf(from), carrierOf(to));
	}

	/** The conversion table over carriers. */
	public static function between(from:OcamlValueCarrier, to:OcamlValueCarrier):Null<OcamlValueConversionKind> {
		return switch [from, to] {
			case [NativePrimitive(source), NativePrimitive(target)] if (source == target):
				SameCarrier;
			case [NullablePrimitive(source), NullablePrimitive(target)] if (source == target):
				SameCarrier;
			case [NativeEnum(source), NativeEnum(target)] if (source == target):
				SameCarrier;
			case [NullableEnum(source), NullableEnum(target)] if (source == target):
				SameCarrier;
			case [DynamicObj, DynamicObj] | [ObjectReference, ObjectReference] | [TypeParameterValue, TypeParameterValue]:
				SameCarrier;
			case [NativePrimitive(source), NullablePrimitive(target)] if (source == target):
				BoxNullable;
			case [NativePrimitive(IntCarrier), NullablePrimitive(FloatCarrier)]:
				BoxIntAsNullableFloat;
			case [NullablePrimitive(source), NativePrimitive(target)] if (source == target):
				UnboxNullablePrimitive(target);
			case [NativeEnum(source), NullableEnum(target)] if (source == target && usesHaxeEnumRuntime(target)):
				BoxNullable;
			case [NullableEnum(source), NativeEnum(target)] if (source == target):
				UnboxObj;
			case [DynamicObj, NativeEnum(target)] | [DynamicObj, NullableEnum(target)] if (usesHaxeEnumRuntime(target)):
				UnboxDynamicEnum(target);
			case [DynamicObj, NativeEnum(_)] | [DynamicObj, NullableEnum(_)] | [DynamicObj, ObjectReference]:
				UnboxObj;
			case [NullablePrimitive(BoolCarrier), DynamicObj]:
				TagNullableBool;
			case [DynamicObj, NullablePrimitive(BoolCarrier)]:
				UntagNullableBool;
			case [DynamicObj, NativePrimitive(BoolCarrier)]:
				// The checked unbox accepts the tagged and the plain form.
				UnboxNullablePrimitive(BoolCarrier);
			case [DynamicObj, TypeParameterValue]:
				// Generic code such as `get_value():T return cast stored;` relies on this
				// `Obj.obj`: it gives the method the polymorphic OCaml result type `'a`, so a
				// caller at a concrete type uses the result without a conversion.
				UnboxObj;
			case [TypeParameterValue, NativePrimitive(primitive)]:
				UnboxNullablePrimitive(primitive);
			case [TypeParameterValue, ObjectReference] | [TypeParameterValue, FunctionValue]:
				UnboxObj;
			case _:
				null;
		}
	}

	static function primitiveOf(type:Type):Null<OcamlPrimitiveCarrier> {
		return switch (OcamlDynamicCarrierModel.followNoAbstracts(type)) {
			case TAbstract(abstractRef, _):
				final abstractType = abstractRef.get();
				switch [(abstractType.pack ?? []).join("."), abstractType.name] {
					case ["", "Int"] | ["haxe", "Int32"]:
						IntCarrier;
					case ["", "Float"]:
						FloatCarrier;
					case ["", "Bool"]:
						BoolCarrier;
					case _:
						null;
				}
			case _:
				null;
		}
	}

	static function enumIdOf(type:Type):Null<String> {
		return switch (type) {
			case TEnum(enumRef, _):
				final enumType = enumRef.get();
				(enumType.pack ?? []).concat([enumType.name]).join(".");
			case _:
				null;
		}
	}

	/** Native interop enums in the `ocaml` package do not use the Haxe enum runtime contract. */
	static function usesHaxeEnumRuntime(semanticTypeId:String):Bool {
		return !StringTools.startsWith(semanticTypeId, "ocaml.");
	}

	static function isCoreNull(abstractType:AbstractType):Bool {
		return (abstractType.pack ?? []).length == 0 && abstractType.name == "Null";
	}
}
#end
