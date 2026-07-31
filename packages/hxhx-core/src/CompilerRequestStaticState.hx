/**
	Clears temporary compiler data that older Stage3 code still stores globally.

	A `static` field belongs to the whole native hxhx process, not to one compile
	request. Most of the compiler already constructs fresh parser, resolver, typer,
	macro, and backend objects for each request. The remaining bootstrap-era
	OCaml emitter still keeps temporary state in static fields, however. If a
	request fails before that helper restores its previous values, the next
	request could otherwise observe stale data. Source-native targets are no
	longer part of this reset seam: each rendered program owns its target state.

	This class is the complete owner list for that temporary compatibility seam.
	It clears those fields before compiler work starts and again during request
	cleanup. It does not retain parsed or typed modules and is never a reusable
	cache payload. The Stage3 OCaml emitter is a serialized bootstrap/diagnostic
	path until the standalone reflaxe.ocaml target replaces it; it cannot earn a
	shared-target readiness claim. Remove this reset when that hard cut retires the
	emitter instead of building a second durable renderer lifecycle around it.
**/
class CompilerRequestStaticState {
	public static function reset():Void {
		EmitterStage.resetRequestState();
	}
}
