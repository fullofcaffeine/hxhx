package hxhx.macro;

/** A type hxhx cannot describe to a macro yet; the service answers `unsupported`. */
class MacroTypeUnsupported {
	public final message:String;

	public function new(message:String) {
		this.message = message;
	}
}
