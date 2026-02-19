/**
	Visibility marker for declarations in the `hih-compiler` subset AST.

	Why:
	- Stage 3 typing needs a deterministic representation for member access.
	- Upstream Haxe treats `public` / `private` as modifiers with default rules.
	  Making this explicit early prevents “stringly typed” modifier logic from
	  leaking everywhere.

	What:
	- `Public` and `Private` only (for now).

	How:
	- We default to `Public` when no modifier is present. This matches Haxe’s
	  default field visibility behavior.
**/
enum HxVisibility {
	Public;
	Private;
}
