package reflaxe.ocaml.lowered;

#if (macro || reflaxe_runtime)
import haxe.macro.Type.TypedExpr;
import reflaxe.ocaml.lowered.OcamlLoweredOrigin.OcamlLoweredSourceSpan;
import reflaxe.ocaml.runtimegen.OcamlRuntimeUseModel.OcamlRuntimeUseOccurrence;

/** Place forms currently understood by the typed OCaml lowering model. */
enum abstract OcamlLoweredPlaceKind(String) from String to String {
	final InstanceField = "instance-field";
	final StaticField = "static-field";
	final ArrayElement = "array-element";
}

/** How a static ref cell is named from the currently emitted OCaml module. */
enum abstract OcamlLoweredStaticFieldAccess(String) from String to String {
	final Local = "local";
	final Qualified = "qualified";
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
	final Index = "index";
	final Load = "load";
	final RightHandSide = "right-hand-side";
	final Operator = "operator";
	final Store = "store";
	final Result = "result";
}

/** How the place operation obtains its Haxe result. */
enum abstract OcamlAssignmentResultKind(String) from String to String {
	final AssignedValue = "assigned-value";
	final ComputedValue = "computed-value";
	final OldValue = "old-value";
}

/** Target-independent integer operation selected before OCaml syntax exists. */
enum abstract OcamlLoweredIntOperator(String) from String to String {
	final Add = "int-add";
}

/** Source update token retained independently from its numeric operation. */
enum abstract OcamlLoweredUpdateOperator(String) from String to String {
	final Increment = "increment";
	final Decrement = "decrement";
}

/** Prefix/postfix syntax retained independently from update result semantics. */
enum abstract OcamlLoweredUpdateFixity(String) from String to String {
	final Prefix = "prefix";
	final Postfix = "postfix";
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

/** Target-owned facts for a mutable static field represented by an OCaml ref. */
typedef OcamlLoweredStaticFieldPlace = {
	final id:String;
	final kind:OcamlLoweredPlaceKind;
	final ownerModuleId:String;
	final ownerTypeName:String;
	final targetSymbolId:String;
	final fieldName:String;
	final targetModuleName:String;
	final targetValueName:String;
	final staticAccess:OcamlLoweredStaticFieldAccess;
	final forwardDeclarationRequired:Bool;
	final semanticTypeId:String;
	final carrierTypeId:String;
	final representationId:String;
	final representationReason:String;
}

/** Target-owned facts for one exact `Array<Int>` element place. */
typedef OcamlLoweredArrayElementPlace = {
	final id:String;
	final kind:OcamlLoweredPlaceKind;
	final ownerModuleId:String;
	final ownerTypeName:String;
	final targetSymbolId:String;
	final receiverSemanticTypeId:String;
	final receiverDisplayType:String;
	final receiverCarrierTypeId:String;
	final receiverRepresentationId:String;
	final receiverRepresentationReason:String;
	final indexSemanticTypeId:String;
	final indexDisplayType:String;
	final indexCarrierTypeId:String;
	final indexRepresentationId:String;
	final indexRepresentationReason:String;
	final fieldName:String;
	final targetModuleName:String;
	final targetLoadName:String;
	final targetStoreName:String;
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

/** A value-producing assignment to a mutable static OCaml ref cell. */
typedef OcamlLoweredStaticSimpleAssignment = {
	final id:String;
	final originId:String;
	final source:OcamlLoweredSourceSpan;
	final semanticTypeId:String;
	final carrierTypeId:String;
	final place:OcamlLoweredStaticFieldPlace;
	final rightHandSide:TypedExpr;
	final conversion:OcamlLoweredConversionKind;
	final result:OcamlAssignmentResultKind;
	final schedule:Array<OcamlPlaceOccurrence>;
	final effects:Array<OcamlLoweredEffect>;
	final runtimeRequirementIds:Array<String>;
}

/** A typed exact-Int static `+=` with an explicit old-cell load. */
typedef OcamlLoweredStaticCompoundAssignment = {
	final id:String;
	final originId:String;
	final source:OcamlLoweredSourceSpan;
	final semanticTypeId:String;
	final carrierTypeId:String;
	final place:OcamlLoweredStaticFieldPlace;
	final rightHandSide:TypedExpr;
	final operation:OcamlLoweredIntOperator;
	final conversion:OcamlLoweredConversionKind;
	final result:OcamlAssignmentResultKind;
	final schedule:Array<OcamlPlaceOccurrence>;
	final effects:Array<OcamlLoweredEffect>;
	final runtimeRequirementIds:Array<String>;
}

/** A typed ordinary Int static update with explicit fixity and result. */
typedef OcamlLoweredStaticIntUpdate = {
	final id:String;
	final originId:String;
	final source:OcamlLoweredSourceSpan;
	final semanticTypeId:String;
	final carrierTypeId:String;
	final place:OcamlLoweredStaticFieldPlace;
	final sourceOperator:OcamlLoweredUpdateOperator;
	final fixity:OcamlLoweredUpdateFixity;
	final operation:OcamlLoweredIntOperator;
	final delta:Int;
	final conversion:OcamlLoweredConversionKind;
	final result:OcamlAssignmentResultKind;
	final schedule:Array<OcamlPlaceOccurrence>;
	final effects:Array<OcamlLoweredEffect>;
	final runtimeRequirementIds:Array<String>;
}

/** A value-producing assignment to one exact `Array<Int>` element. */
typedef OcamlLoweredArraySimpleAssignment = {
	final id:String;
	final originId:String;
	final source:OcamlLoweredSourceSpan;
	final semanticTypeId:String;
	final carrierTypeId:String;
	final place:OcamlLoweredArrayElementPlace;
	final receiver:TypedExpr;
	final index:TypedExpr;
	final rightHandSide:TypedExpr;
	final conversion:OcamlLoweredConversionKind;
	final result:OcamlAssignmentResultKind;
	final schedule:Array<OcamlPlaceOccurrence>;
	final effects:Array<OcamlLoweredEffect>;
	final runtimeRequirementIds:Array<String>;
	final runtimeUseOccurrences:Array<OcamlRuntimeUseOccurrence>;
}

/** A typed exact-Int array `+=` with an explicit old-element load. */
typedef OcamlLoweredArrayCompoundAssignment = {
	final id:String;
	final originId:String;
	final source:OcamlLoweredSourceSpan;
	final semanticTypeId:String;
	final carrierTypeId:String;
	final place:OcamlLoweredArrayElementPlace;
	final receiver:TypedExpr;
	final index:TypedExpr;
	final rightHandSide:TypedExpr;
	final operation:OcamlLoweredIntOperator;
	final conversion:OcamlLoweredConversionKind;
	final result:OcamlAssignmentResultKind;
	final schedule:Array<OcamlPlaceOccurrence>;
	final effects:Array<OcamlLoweredEffect>;
	final runtimeRequirementIds:Array<String>;
}

/** A typed ordinary Int array update with explicit fixity and result. */
typedef OcamlLoweredArrayIntUpdate = {
	final id:String;
	final originId:String;
	final source:OcamlLoweredSourceSpan;
	final semanticTypeId:String;
	final carrierTypeId:String;
	final place:OcamlLoweredArrayElementPlace;
	final receiver:TypedExpr;
	final index:TypedExpr;
	final sourceOperator:OcamlLoweredUpdateOperator;
	final fixity:OcamlLoweredUpdateFixity;
	final operation:OcamlLoweredIntOperator;
	final delta:Int;
	final conversion:OcamlLoweredConversionKind;
	final result:OcamlAssignmentResultKind;
	final schedule:Array<OcamlPlaceOccurrence>;
	final effects:Array<OcamlLoweredEffect>;
	final runtimeRequirementIds:Array<String>;
}

/** A typed ordinary Int compound assignment with an explicit old-value load. */
typedef OcamlLoweredCompoundAssignment = {
	final id:String;
	final originId:String;
	final source:OcamlLoweredSourceSpan;
	final semanticTypeId:String;
	final carrierTypeId:String;
	final place:OcamlLoweredInstanceFieldPlace;
	final receiver:TypedExpr;
	final rightHandSide:TypedExpr;
	final operation:OcamlLoweredIntOperator;
	final conversion:OcamlLoweredConversionKind;
	final result:OcamlAssignmentResultKind;
	final schedule:Array<OcamlPlaceOccurrence>;
	final effects:Array<OcamlLoweredEffect>;
	final runtimeRequirementIds:Array<String>;
}

/** A typed ordinary Int update with explicit fixity, mutation, and result. */
typedef OcamlLoweredIntUpdate = {
	final id:String;
	final originId:String;
	final source:OcamlLoweredSourceSpan;
	final semanticTypeId:String;
	final carrierTypeId:String;
	final place:OcamlLoweredInstanceFieldPlace;
	final receiver:TypedExpr;
	final sourceOperator:OcamlLoweredUpdateOperator;
	final fixity:OcamlLoweredUpdateFixity;
	final operation:OcamlLoweredIntOperator;
	final delta:Int;
	final conversion:OcamlLoweredConversionKind;
	final result:OcamlAssignmentResultKind;
	final schedule:Array<OcamlPlaceOccurrence>;
	final effects:Array<OcamlLoweredEffect>;
	final runtimeRequirementIds:Array<String>;
}

/** Closed typed place-operation families currently admitted by the target. */
enum OcamlLoweredPlaceOperation {
	Simple(plan:OcamlLoweredSimpleAssignment);
	StaticSimple(plan:OcamlLoweredStaticSimpleAssignment);
	StaticCompound(plan:OcamlLoweredStaticCompoundAssignment);
	StaticUpdate(plan:OcamlLoweredStaticIntUpdate);
	ArraySimple(plan:OcamlLoweredArraySimpleAssignment);
	ArrayCompound(plan:OcamlLoweredArrayCompoundAssignment);
	ArrayUpdate(plan:OcamlLoweredArrayIntUpdate);
	Compound(plan:OcamlLoweredCompoundAssignment);
	Update(plan:OcamlLoweredIntUpdate);
}

/** Stable human-readable projection of every currently admitted place kind. */
typedef OcamlLoweredPlaceReport = {
	final id:String;
	final kind:OcamlLoweredPlaceKind;
	final ownerModuleId:String;
	final ownerTypeName:String;
	final targetSymbolId:String;
	final fieldName:String;
	final semanticTypeId:String;
	final carrierTypeId:String;
	final representationId:String;
	final representationReason:String;
	final ?targetFieldName:String;
	final ?receiverSemanticTypeId:String;
	final ?receiverDisplayType:String;
	final ?receiverCarrierTypeId:String;
	final ?receiverRepresentationId:String;
	final ?receiverRepresentationReason:String;
	final ?indexSemanticTypeId:String;
	final ?indexDisplayType:String;
	final ?indexCarrierTypeId:String;
	final ?indexRepresentationId:String;
	final ?indexRepresentationReason:String;
	final ?targetModuleName:String;
	final ?targetValueName:String;
	final ?targetLoadName:String;
	final ?targetStoreName:String;
	final ?staticAccess:OcamlLoweredStaticFieldAccess;
	final ?forwardDeclarationRequired:Bool;
}

/** Serializable form retained after target syntax has been constructed. */
typedef OcamlLoweredPlaceReportEntry = {
	final id:String;
	final originId:String;
	final source:OcamlLoweredSourceSpan;
	final nodeKind:String;
	final semanticTypeId:String;
	final carrierTypeId:String;
	final place:OcamlLoweredPlaceReport;
	final ?operation:OcamlLoweredIntOperator;
	final ?sourceOperator:OcamlLoweredUpdateOperator;
	final ?fixity:OcamlLoweredUpdateFixity;
	final ?delta:Int;
	final conversion:OcamlLoweredConversionKind;
	final result:OcamlAssignmentResultKind;
	final schedule:Array<OcamlPlaceOccurrence>;
	final effects:Array<OcamlLoweredEffect>;
	final runtimeRequirementIds:Array<String>;
}
#end
