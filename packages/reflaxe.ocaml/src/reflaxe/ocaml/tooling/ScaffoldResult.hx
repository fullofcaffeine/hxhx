package reflaxe.ocaml.tooling;

/** Closed success/failure result for scaffold creation. **/
enum ScaffoldResult {
	Created(summary:ScaffoldSummary);
	Rejected(message:String);
}
