/**
	The resolved meaning of one parsed Haxe `import` or `using` declaration.

	Unlike the parsed directive kind, this family records what typing proved the
	path refers to. A type import or `using` directive may select several eligible
	types from one Haxe module; `TyModuleDirective` carries that complete provider
	set. Targets can therefore distinguish `import model.Api.PI` from a type import
	without guessing from capitalization or target-language syntax.
**/
enum TyModuleDirectiveKind {
	TypeImport;
	StaticMemberImport(memberName:String);
	StaticWildcardImport;
	PackageWildcardImport;
	UsingType;
	Unresolved;
}
