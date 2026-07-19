package reflaxe.ocaml.tooling;

/** Files and identity committed by one successful project scaffold transaction. **/
typedef ScaffoldSummary = {
	final kind:String;
	final projectName:String;
	final destination:String;
	final files:Array<String>;
}
