/**
	A separate-module nominal value used to prove callable result qualification.

	The class remains inside the first monomorphic carrier subset: it has no
	inheritance, interface, generic, extern, or dynamic-method behavior.
**/
class SourcePos {
	public var index:Int;

	public function new(index:Int) {
		this.index = index;
	}
}
