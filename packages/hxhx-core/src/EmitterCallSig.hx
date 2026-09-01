/**
	Describes the OCaml parameters produced for one Haxe function declaration.

	Stage3 records this once, then uses it when emitting calls so optional, rest,
	receiver, Float, and Int64 arguments cross the same declared boundary as the
	function definition.
**/
typedef EmitterCallSig = {
	/** Total OCaml parameters after lowering (includes the rest-array parameter when present). */
	final expected:Int;

	/** Required OCaml parameters after lowering (receiver + non-optional params). */
	final required:Int;

	/** Number of fixed (non-rest) parameters. */
	final fixed:Int;

	/** Whether the final parameter is a lowered rest-args array. */
	final hasRest:Bool;

	/** Whether this lowered call expects a synthetic receiver parameter. */
	final needsReceiver:Bool;

	/** Parameter names after lowering, aligned with emitted OCaml arguments. */
	final paramNames:Array<String>;

	/** Whether each lowered fixed parameter can be filled from an omitted Haxe argument. */
	final paramFillable:Array<Bool>;

	/** Parameter type hints after lowering, aligned with emitted OCaml arguments. */
	final paramTypeHints:Array<String>;

	/** Declared Haxe result type used to classify a call expression before target emission. */
	final resultTypeHint:String;
}
