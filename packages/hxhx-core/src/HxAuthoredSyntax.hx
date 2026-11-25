/**
	Names that authored parsing (`ParserStage.parseAuthored`, the parse oracle) uses to keep
	upstream syntax that ordinary parsing lowers.

	Kept outside `HxParser`: the OCaml backend cannot emit a static with an initializer inside
	HxParser's module cycle (`ocaml-module-cycle:unsupported-initialization`).
**/
class HxAuthoredSyntax {
	/** Expression metadata as written: `ECall(EIdent(META), [EString(name with colon), EString(arguments text), expr])`. */
	public static inline final META = "__hxhx_authored_meta";
}
