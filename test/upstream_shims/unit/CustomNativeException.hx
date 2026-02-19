package unit;

/**
	Upstream test shim: `unit.CustomNativeException`.

	Why
	- Upstream `tests/unit/src/unit/TestExceptions.hx` defines `CustomNativeException`
	  only for a fixed list of targets (`php`, `js`, `eval`, `hl`, ...).
	- The OCaml target is new, so that conditional does not define the type and the
	  unit suite fails to compile.

	What
	- A minimal throwable class with the expected constructor shape.

	How / semantics
	- Upstream’s `eval/neko/hl/cpp` branch uses a similarly minimal class which does
	  not extend any platform-native exception base type.
	- This is sufficient for the early Gate1/Gate2 bring-up stages where we mainly
	  care about *typing* and basic throw/catch flows.

	Notes
	- This file is intentionally only added to the classpath by the upstream test
	  runners (see `scripts/hxhx/run-upstream-unit-macro-ocaml.sh`).
**/
class CustomNativeException {
	public function new(m:String) {}
}
