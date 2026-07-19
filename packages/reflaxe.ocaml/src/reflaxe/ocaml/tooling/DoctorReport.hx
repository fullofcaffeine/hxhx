package reflaxe.ocaml.tooling;

/** Capability groups derived from the individual doctor checks. **/
typedef DoctorCapabilities = {
	final sourceGeneration:Bool;
	final nativeBuild:Bool;
	final compilerAuthoring:Bool;
	final hxhxHost:Bool;
	final reproduciblePackaging:Bool;
	final verifiedReleaseLane:Bool;
}

/** The exact hosted toolchain used by the current package evidence lane. **/
typedef DoctorVerifiedToolchain = {
	final haxe:String;
	final ocaml:String;
	final dune:String;
	final hosts:Array<String>;
}

/** Aggregate counts and the exit decision for the requested capability. **/
typedef DoctorSummary = {
	final pass:Int;
	final warn:Int;
	final fail:Int;
	final skip:Int;
	final requestedCapability:String;
	final ready:Bool;
	final exitCode:Int;
}

/**
	Stable machine-readable output from `reflaxe.ocaml doctor --json`.

	The schema reports present capabilities separately from the exact hosted
	release lane. A compatible but unverified local OCaml version can therefore
	remain useful without being mistaken for verified package evidence.
**/
typedef DoctorReport = {
	final schemaVersion:Int;
	final packageName:String;
	final packageVersion:String;
	final projectRoot:String;
	final platform:String;
	final architecture:String;
	final verifiedToolchain:DoctorVerifiedToolchain;
	final checks:Array<DoctorCheck>;
	final capabilities:DoctorCapabilities;
	final summary:DoctorSummary;
}
