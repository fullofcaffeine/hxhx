/**
	Proves that the untyped Void exception does not bypass call-plan ownership.

	Static initializers have no sealed function occurrence in this compiler rung.
	The target must therefore reject this call before it writes OCaml output.
**/
class UnplannedGeneratedEntrypoint {
	static final result:Dynamic = untyped GeneratedEntrypoint.init();

	static function main():Void {
		Sys.println(result);
	}
}
