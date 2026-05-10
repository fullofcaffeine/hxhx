/**
	Visibility marker for declarations in the `hih-compiler` subset AST.

	Why:
	- Stage 3 typing needs a deterministic representation for member access.
	- Upstream Haxe treats `public` / `private` as modifiers with default rules.
	  Making this explicit early prevents "stringly typed" modifier logic from
	  leaking everywhere.

	What:
	- `Public` and `Private` only (for now).

	How:
	- Class fields default to `Private` when no visibility modifier is present.
	  This matches Haxe class member visibility and lets using-extension checks
	  distinguish explicit public helpers from private implementation helpers.
**/
enum HxVisibility {
	Public;
	Private;
}
