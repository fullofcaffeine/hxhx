/** Closed runtime targets admitted by shared typing; numeric and enum targets require separate contracts. */
enum TypedRuntimeTypeKind {
	Nominal(identity:TyNominalTypeId);
	ArrayCore;
	StringCore;
}
