package hxhx;

/**
	Boxes heterogeneous JSON arrays at the compiler metadata boundary.

	The wrapper keeps array values represented consistently in no-prepass OCaml builds.
	Schema-specific readers unwrap `values` and immediately validate their element types.
**/
class CompilerJsonArray {
	public final values:Array<Dynamic>;

	public function new(values:Array<Dynamic>) {
		this.values = values;
	}
}
