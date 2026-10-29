/**
	The result of one diagnostic query during ordinary function inference.
	Projection consumes this result instead of retyping intentionally invalid input
	after the function's inference variables and control destinations are sealed.
	Only source diagnostics become Rejected; internal compiler failures propagate.
 */
enum TyDiagnosticProbeOutcome {
	Accepted(type:TyType);
	Rejected(message:String);
}
