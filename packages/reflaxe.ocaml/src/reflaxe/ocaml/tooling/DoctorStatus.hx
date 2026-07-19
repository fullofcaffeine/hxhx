package reflaxe.ocaml.tooling;

/** Stable status values used by human and JSON doctor reports. **/
enum abstract DoctorStatus(String) from String to String {
	var Pass = "pass";
	var Warn = "warn";
	var Fail = "fail";
	var Skip = "skip";
}
