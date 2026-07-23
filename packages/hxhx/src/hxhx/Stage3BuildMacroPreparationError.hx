package hxhx;

/**
	Reports a request-local failure while preparing one module's build macros.

	The separate cancellation flag lets the Stage3 driver preserve exit code 130
	instead of presenting a cooperative timeout as a source or macro error.
**/
class Stage3BuildMacroPreparationError extends haxe.Exception {
	public final cancelled:Bool;

	public function new(message:String, cancelled:Bool = false) {
		super(message);
		this.cancelled = cancelled;
	}
}
