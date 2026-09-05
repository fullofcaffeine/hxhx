package reflaxe.ocaml.ast;

/** One exact authored-text or typed-argument position in a raw OCaml template. */
enum OcamlRawInterpolationPlanPart {
	AuthoredText(value:String);
	TypedArgument(index:Int);
}
