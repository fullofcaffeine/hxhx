package reflaxe.ocaml.tooling;

/** Captured result from one small, non-interactive toolchain probe. **/
typedef CommandResult = {
	final code:Int;
	final stdout:String;
	final stderr:String;
}
