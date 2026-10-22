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

	/** Exclusive original-source host string index; synthetic tokens can lack this fact. */
	public final endIndex:Null<Int>;

	public function new(kind:HxTokenKind, pos:HxPos, ?numericText:String, ?numericSuffix:String, ?endIndex:Int) {
		this.kind = kind;
		this.pos = pos;
		this.numericText = numericText;
		this.numericSuffix = numericSuffix;
		this.endIndex = endIndex;
	}

	public function getKind():HxTokenKind {
		return kind;
	}

	public function getPos():HxPos {
		return pos;
	}
}
