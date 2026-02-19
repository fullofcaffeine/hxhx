/**
	Token value produced by the Haxe-in-Haxe lexer.

	Why:
	- We want the shape of a real compiler pipeline: source -> tokens -> AST.
	- Carrying source positions in tokens enables meaningful diagnostics early.
**/
class HxToken {
	public final kind:HxTokenKind;
	public final pos:HxPos;

	public function new(kind:HxTokenKind, pos:HxPos) {
		this.kind = kind;
		this.pos = pos;
	}
}

