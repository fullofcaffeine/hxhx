package reflaxe.ocaml.lowered;

#if (macro || reflaxe_runtime)
import haxe.macro.Type.TypedExpr;
import reflaxe.ocaml.lowered.OcamlLoweredOrigin.OcamlLoweredSourceSpan;

/** Place forms currently understood by the typed OCaml lowering model. */
enum abstract OcamlLoweredPlaceKind(String) from String to String {
	final InstanceField = "instance-field";
}

/** Observable or conservative effects recorded before target syntax exists. */
enum abstract OcamlLoweredEffect(String) from String to String {
	final Read = "read";
	final Write = "write";
	final Call = "call";
	final Throw = "throw";
}

/** Ordered roles in a value-producing assignment schedule. */
enum abstract OcamlPlaceOccurrenceRole(String) from String to String {
	final Receiver = "receiver";
	final RightHandSide = "right-hand-side";
	final Store = "store";
	final Result = "result";
}

/** How the assignment expression obtains its Haxe result. */
enum abstract OcamlAssignmentResultKind(String) from String to String {
	final AssignedValue = "assigned-value";
}

/** The selected conversion between an input value and a place carrier. */
enum abstract OcamlLoweredConversionKind(String) from String to String {
	final Identity = "identity";
}

/** One required occurrence in source-observable evaluation order. */
typedef OcamlPlaceOccurrence = {
	final id:String;
	final role:OcamlPlaceOccurrenceRole;
	final sourceId:String;
	final occurrenceCount:Int;
	final sharedAs:Null<String>;
	final effects:Array<OcamlLoweredEffect>;
}

/** Target-owned facts for a record-backed instance field. */
typedef OcamlLoweredInstanceFieldPlace = {
	final id:String;
	final kind:OcamlLoweredPlaceKind;
	final ownerModuleId:String;
	final ownerTypeName:String;
	final targetSymbolId:String;
	final receiverSemanticTypeId:String;
	final receiverCarrierTypeId:String;
	final receiverRepresentationId:String;
	final receiverRepresentationReason:String;
	final fieldName:String;
	final targetFieldName:String;
	final semanticTypeId:String;
	final carrierTypeId:String;
	final representationId:String;
	final representationReason:String;
}

/** First typed lowered node: a value-producing simple field assignment. */
typedef OcamlLoweredSimpleAssignment = {
	final id:String;
	final originId:String;
	final source:OcamlLoweredSourceSpan;
	final semanticTypeId:String;
	final carrierTypeId:String;
	final place:OcamlLoweredInstanceFieldPlace;
	final receiver:TypedExpr;
	final rightHandSide:TypedExpr;
	final conversion:OcamlLoweredConversionKind;
	final result:OcamlAssignmentResultKind;
	final schedule:Array<OcamlPlaceOccurrence>;
	final effects:Array<OcamlLoweredEffect>;
	final runtimeRequirementIds:Array<String>;
}

/** Serializable form retained after target syntax has been constructed. */
typedef OcamlLoweredPlaceReportEntry = {
	final id:String;
	final originId:String;
	final source:OcamlLoweredSourceSpan;
	final nodeKind:String;
	final semanticTypeId:String;
	final carrierTypeId:String;
	final place:OcamlLoweredInstanceFieldPlace;
	final conversion:OcamlLoweredConversionKind;
	final result:OcamlAssignmentResultKind;
	final schedule:Array<OcamlPlaceOccurrence>;
	final effects:Array<OcamlLoweredEffect>;
	final runtimeRequirementIds:Array<String>;
}
#end
