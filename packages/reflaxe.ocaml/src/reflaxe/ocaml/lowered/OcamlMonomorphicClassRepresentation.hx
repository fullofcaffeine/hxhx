package reflaxe.ocaml.lowered;

#if (macro || reflaxe_runtime)
/**
	One field in the record layout of an admitted monomorphic Haxe class.

	The entry stores semantic and canonical target identities. It does not store
	rendered OCaml syntax: callers decide whether the nominal type needs a module
	qualifier at the point where syntax is constructed.
**/
typedef OcamlMonomorphicClassField = {
	final sourceFieldName:String;
	final targetFieldName:String;
	final semanticTypeId:String;
	final carrierTypeId:String;
	final representationId:String;
	final declarationOrder:Int;
}

/**
	Sealed nominal record layout for one whole-program-monomorphic user class.

	This is deliberately not a general class hierarchy model. Inheritance,
	interfaces, generics, externs, dynamic methods, and native boundaries require
	different carriers or conversions and are excluded from this decision.
**/
typedef OcamlMonomorphicClassDecision = {
	final id:String;
	final key:String;
	final programRevision:String;
	final revision:String;
	final semanticTypeId:String;
	final sourceModuleId:String;
	final sourceTypeName:String;
	final targetModuleName:String;
	final targetTypeName:String;
	final canonicalCarrierTypeId:String;
	final fields:Array<OcamlMonomorphicClassField>;
	final proofId:String;
	final proofClaim:String;
}
#end
