/**
	Immutable external-file inputs explicitly registered for one Haxe module.

	Entries are sorted by path revision and equivalent duplicates are coalesced.
	Two observations of the same path that disagree on file state or content fail
	instead of silently publishing an ambiguous dependency snapshot.
**/
class CompilerMacroFileDependencyObservation {
	static final EMPTY = new CompilerMacroFileDependencyObservation([]);

	final inputs:Array<CompilerMacroFileDependencyInput>;
	final canonicalIdentity:String;

	public function new(inputs:Array<CompilerMacroFileDependencyInput>) {
		final sorted = inputs == null ? [] : inputs.copy();
		sorted.sort(compareInputs);
		this.inputs = [];
		var previous:Null<CompilerMacroFileDependencyInput> = null;
		for (input in sorted) {
			if (input == null)
				throw "macro file dependency observation contains a null input";
			if (previous != null && previous.getPathIdentityRevision() == input.getPathIdentityRevision()) {
				if (previous.getCanonicalIdentity() != input.getCanonicalIdentity())
					throw "macro file dependency observation contains conflicting observations for one path identity";
				continue;
			}
			this.inputs.push(input);
			previous = input;
		}
		final values = new Array<Null<String>>();
		values.push("macro-file-dependency-observation-v1");
		values.push(Std.string(this.inputs.length));
		for (input in this.inputs)
			values.push(input.getCanonicalIdentity());
		canonicalIdentity = CompilerCacheIdentity.encode(values);
	}

	public static function empty():CompilerMacroFileDependencyObservation
		return EMPTY;

	public function getInputs():Array<CompilerMacroFileDependencyInput>
		return inputs.copy();

	public function getCanonicalIdentity():String
		return canonicalIdentity;

	static function compareInputs(left:CompilerMacroFileDependencyInput, right:CompilerMacroFileDependencyInput):Int {
		final leftKey = left.getPathIdentityRevision();
		final rightKey = right.getPathIdentityRevision();
		return leftKey < rightKey ? -1 : (leftKey > rightKey ? 1 : 0);
	}
}
