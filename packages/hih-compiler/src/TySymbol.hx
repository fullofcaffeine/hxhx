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
	public final ty:TyType;

	public function new(name:String, ty:TyType) {
		this.name = name;
		this.ty = ty;
	}

	public function getName():String return name;
	public function getType():TyType return ty;
}
