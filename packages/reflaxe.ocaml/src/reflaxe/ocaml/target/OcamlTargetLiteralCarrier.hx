package reflaxe.ocaml.target;

/**
	Describes the representation required by a literal's destination.

	Both literal lowering and runtime authorization use these facts. Keeping the
	enum independent lets each module refer to it without creating an OCaml
	module dependency cycle when the shared target is compiled natively.
**/
enum OcamlTargetLiteralCarrier {
	Direct;
	NullableInt;
	NullableFloat;
	NullableBool;
	DynamicOrTypeParameter;
}
