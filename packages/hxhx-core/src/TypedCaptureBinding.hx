/** The execution event that creates a fresh instance of a captured source binding. */
enum TypedCaptureCreation {
	FunctionEntry;
	Declaration;
	LoopIteration;
	PatternMatch;
	CatchEntry;
}

/**
	Connects an exact declaration to its lexical function and allocation event.
	The occurrence and slot identify source execution, not one global allocation:
	each invocation, iteration, or selected declaration can create fresh storage.
 */
class TypedCaptureBinding {
	public final binding:TyLocalBinding;
	public final functionIdentity:String;
	public final occurrence:String;
	public final slot:Int;
	public final creation:TypedCaptureCreation;

	public function new(binding:TyLocalBinding, functionIdentity:String, occurrence:String, slot:Int, creation:TypedCaptureCreation) {
		this.binding = binding;
		this.functionIdentity = functionIdentity;
		this.occurrence = occurrence;
		this.slot = slot;
		this.creation = creation;
	}

	public function getCanonicalIdentity():String
		return CompilerCacheIdentity.encode([
			binding.getCanonicalIdentity(),
			functionIdentity,
			occurrence,
			Std.string(slot),
			Std.string(creation)
		]);
}
