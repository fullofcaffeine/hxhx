/**
	Function declaration AST node for the `hih-compiler` subset.

	Why:
	- Stage 3 typing needs explicit function signatures + bodies.
	- Upstream Haxe allows multiple syntactic forms (`{ ... }`, `return expr;`,
	  `;` for extern/abstract). We need to represent these consistently.

	What:
	- Name, visibility, `static` flag.
	- Parsed argument list (names + optional type hints/default values).
	- Optional return type hint text.
	- Body statements (minimal subset for now).

	How:
	- Like the rest of the Stage 2/3 AST, this is intentionally smaller than the
	  upstream compiler AST. It grows rung-by-rung with acceptance needs.
**/
class HxFunctionDecl {
	public final name:String;
	public final visibility:HxVisibility;
	public final isStatic:Bool;
	public final args:Array<HxFunctionArg>;
	public final returnTypeHint:String;
	public final body:Array<HxStmt>;
	public final returnStringLiteral:String;

	public function new(
		name:String,
		visibility:HxVisibility,
		isStatic:Bool,
		args:Array<HxFunctionArg>,
		returnTypeHint:String,
		body:Array<HxStmt>,
		returnStringLiteral:String
	) {
		this.name = name;
		this.visibility = visibility;
		this.isStatic = isStatic;
		this.args = args;
		this.returnTypeHint = returnTypeHint;
		this.body = body;
		this.returnStringLiteral = returnStringLiteral;
	}

	public function getFirstReturnExpr():HxExpr {
		function find(stmts:Array<HxStmt>):Null<HxExpr> {
			for (s in stmts) {
				switch (s) {
					case SReturn(e, _):
						return e;
					case SReturnVoid(_):
						return EUnsupported("<return-void>");
					case SBlock(ss, _):
						final r = find(ss);
						if (r != null) return r;
					case SIf(_cond, thenBranch, elseBranch, _):
						// Pre-order: then, then else. This is a bootstrap heuristic for “first return”.
						final r1 = find([thenBranch]);
						if (r1 != null) return r1;
						if (elseBranch != null) {
							final r2 = find([elseBranch]);
							if (r2 != null) return r2;
						}
					case _:
				}
			}
			return null;
		}

		final r = find(body);
		return r == null ? EUnsupported("<no-return>") : r;
	}

	/**
		Non-inline getters for cross-module use.

		Why:
		- OCaml builds under dune’s `-opaque` treat record labels as implementation
		  details, so other compilation units cannot reliably access fields
		  directly (`fn.isStatic`, `fn.name`, ...).
		- Using non-inline getters keeps the bootstrap examples compiling without
		  weakening dune’s warning discipline.
	**/
	public static function getName(fn:HxFunctionDecl):String return fn.name;
	public static function getVisibility(fn:HxFunctionDecl):HxVisibility return fn.visibility;
	public static function getIsStatic(fn:HxFunctionDecl):Bool return fn.isStatic;
	public static function getArgs(fn:HxFunctionDecl):Array<HxFunctionArg> return fn.args;
	public static function getReturnTypeHint(fn:HxFunctionDecl):String return fn.returnTypeHint;
	public static function getBody(fn:HxFunctionDecl):Array<HxStmt> return fn.body;
	public static function getReturnStringLiteral(fn:HxFunctionDecl):String return fn.returnStringLiteral;
}
