/**
	Symbol table entry for Stage 3 bring-up.

	Why:
	- The typer is fundamentally “name resolution + types”.
	- Even before full typing, we want a stable place to attach:
	  - declared types (from hints)
	  - inferred types (later)
	  - source positions (later)

	What:
	- A name and a `TyType`.

	How:
	- This is deliberately small. As Stage 3 expands, this grows into proper
	  scope tracking (locals, captures, fields, imports, etc.).
**/
class TySymbol {
	public final name:String;

	var ty:TyType;

	public function new(name:String, ty:TyType) {
		this.name = name;
		this.ty = ty;
	}

	public function getName():String
		return name;

	public function getType():TyType
		return ty;

	/**
		Refine a symbol's type during typing.

		Why
		- Stage 3 starts with partial information: a `var x = expr;` has no
		  explicit type hint, but we can infer a type from the initializer.
		- For bootstrapping, we prefer “refine in place” so all subsequent lookups
		  of `x` see the improved type.

		How
		- This is intentionally tiny and unsafe compared to upstream Haxe’s
		  monomorph/unification engine.
		- Callers must keep updates deterministic: only refine from `Unknown` or
		  from compatible types.
	**/
	public function setType(t:TyType):Void {
		this.ty = t;
	}
}
