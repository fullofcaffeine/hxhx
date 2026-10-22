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
	- Ordinary class members default to `Private`; extern members default to
	  `Public`. Written modifiers override that default. Extension lookup uses
	  this effective visibility without reconstructing the source modifiers.
**/
enum HxVisibility {
	Public;
	Private;
}
