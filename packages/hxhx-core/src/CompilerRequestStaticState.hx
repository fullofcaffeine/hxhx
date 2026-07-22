import backend.cpp.CppTargetCore;
import backend.source.SourceTargetCommon;

/**
	Clears temporary compiler data that older Stage3 code still stores globally.

	A `static` field belongs to the whole native hxhx process, not to one compile
	request. Most of the compiler already constructs fresh parser, resolver, typer,
	macro, and backend objects for each request. A few bootstrap-era parser and
	emitter helpers still keep their current module, function, or lookup tables in
	static fields, however. If a request fails before those helpers restore their
	previous values, the next request could otherwise observe stale data.

	This class is the complete owner list for that temporary compatibility seam.
	It clears those fields before compiler work starts and again during request
	cleanup. It does not retain parsed or typed modules and is not a cache. As the
	listed helpers become ordinary request-owned objects, remove them from this
	list instead of adding a second lifecycle path.
**/
class CompilerRequestStaticState {
	public static function reset():Void {
		HxParser.resetRequestState();
		EmitterStage.resetRequestState();
		CppTargetCore.resetRequestState();
		SourceTargetCommon.resetRequestState();
	}
}
