/**
	Interface relationships indexed for one class or interface declaration.

	For a class, types are implemented interfaces. For an interface, types are
	extended interfaces. Early entries can have unresolved provider names. The
	final typed header resolves those names after loading their modules. Neither
	relation selects a superclass constructor.
**/
typedef TyClassInterfaces = {
	final isInterface:Bool;
	final types:Array<TyType>;
}
