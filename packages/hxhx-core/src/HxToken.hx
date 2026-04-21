/**
	Token value produced by the Haxe-in-Haxe lexer.

	Why:
	- We want the shape of a real compiler pipeline: source -> tokens -> AST.
	- Carrying source positions in tokens enables meaningful diagnostics early.
**/
class HxToken {
	public final kind:HxTokenKind;
	public final pos:HxPos;
	public final numericText:Null<String>;
	public final numericSuffix:Null<String>;

	public function new(kind:HxTokenKind, pos:HxPos, ?numericText:String, ?numericSuffix:String) {
		this.kind = kind;
		this.pos = pos;
		this.numericText = numericText;
		this.numericSuffix = numericSuffix;
	}

	public function getKind():HxTokenKind {
		return kind;
	}

	public function getPos():HxPos {
		return pos;
	}
}
