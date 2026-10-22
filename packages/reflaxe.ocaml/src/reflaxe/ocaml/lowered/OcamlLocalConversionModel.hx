package reflaxe.ocaml.lowered;

import reflaxe.ocaml.lowered.OcamlRepresentationModel.OcamlRepresentationDomain;

/** The source role that requires one local-carrier conversion. */
enum abstract OcamlLocalConversionRole(String) from String to String {
	final Initializer = "initializer";
	final Assignment = "assignment";
	final Read = "read";
}

/** One function-local reference to a program-owned representation decision. */
typedef OcamlLocalRepresentationReference = {
	final localId:String;
	final representationId:String;
	final representationRevision:String;
	final semanticTypeId:String;
	final domain:OcamlRepresentationDomain;
}
