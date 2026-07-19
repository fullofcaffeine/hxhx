package reflaxe.ocaml.tooling;

/**
	One independently actionable doctor result.

	`requiredForSource` distinguishes the tools needed to emit OCaml from tools
	that enable native builds, compiler authoring, packaging, or hxhx hosting.
**/
typedef DoctorCheck = {
	final id:String;
	final label:String;
	final status:DoctorStatus;
	final requiredForSource:Bool;
	final summary:String;
	final detail:Null<String>;
	final remediation:Null<String>;
	final version:Null<String>;
	final path:Null<String>;
}
