/** Closed runtime targets admitted by shared typing; each backend must validate its supported representations. */
enum TypedRuntimeTypeKind {
	Nominal(identity:TyNominalTypeId);
	EnumDeclaration(identity:TyNominalTypeId);
	ArrayCore;
	StringCore;
	IntCore;
	FloatCore;
	BoolCore;
	DynamicCore;
	ClassCore;
	EnumCore;
}
