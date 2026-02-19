/**
	Bootstrap switch-pattern representation for Stage 3 bring-up.

	Why
	- Upstream-shaped code (notably the `tests/RunCi.hx` harness) uses `switch`
	  both as an expression and as a statement.
	- Stage 3 initially captured `switch` as raw text (`ESwitchRaw`) to keep parsing
	  deterministic, but that prevents running harness-style programs under the
	  Stage3 bootstrap emitter (they need real control flow).

	What
	- A deliberately small pattern subset that is sufficient for orchestrators:
	  - `null`
	  - wildcard `_`
	  - string/int literals
	  - bare enum-like values (Stage3: a bare uppercase identifier such as `Macro`)
	  - binder patterns (`case name:`) used as a catch-all.

	How
	- This is *not* full Haxe `switch` semantics:
	  - no guards (`if`),
	  - limited multiple patterns (`case a | b:`) are supported, but only as a
		shallow OR of simple literals (no guards, no extractors).
	  - no structural patterns / extractors.
	- It is intentionally “bring-up friendly” so we can run unmodified upstream
	  harnesses without copying or translating upstream compiler code.
**/
enum HxSwitchPattern {
	PNull;
	PWildcard;
	PString(value:String);
	PInt(value:Int);
	PEnumValue(name:String);
	PBind(name:String);

	/**
		OR-pattern list: `case a | b | c:`

		Bring-up constraint
		- This is parsed and lowered as a simple boolean OR of each sub-pattern’s
		  condition against the scrutinee.
		- This is *not* the full upstream pattern algebra; it exists primarily to
		  support harness-style code like:
		  `case 'Linux' | 'Windows': ...`
	**/
	POr(patterns:Array<HxSwitchPattern>);
}
