package backend.cpp;

/**
	A resolved local storage location, before evaluating an assignment's value.
	Cell edges need a temporary root across collecting expressions. Lexical roots
	already have stable addresses and remain registered until their scope leaves.
	Direct leaves are invocation-local C++ scalar variables; their ABI type owns
	the exact boxing and unboxing transport and they contain no heap references.
	Source write permission and conversions remain owned by typing and lowering.
 */
enum CppManagedPlace {
	Cell(reference:String);
	LocalRoot(symbol:String);
	DirectLeaf(symbol:String, type:TyType);
}
