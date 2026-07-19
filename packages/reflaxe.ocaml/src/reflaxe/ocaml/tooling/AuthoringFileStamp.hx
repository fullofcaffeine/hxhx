package reflaxe.ocaml.tooling;

/** Stable file facts used to detect one authoring-loop input change. **/
typedef AuthoringFileStamp = {
	final modifiedMilliseconds:Float;
	final size:Float;
}
