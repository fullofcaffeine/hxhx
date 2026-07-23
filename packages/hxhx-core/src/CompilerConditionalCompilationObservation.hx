/**
	Immutable record of the compile-time conditions evaluated for one source module.

	Only evaluated expressions and one-way definition-value revisions participate.
	Unrelated definitions and short-circuited operands therefore do not change the
	identity. Accessors expose definition names for diagnostics, never raw values.
**/
class CompilerConditionalCompilationObservation {
	final decisions:Array<CompilerConditionalDecision>;
	final inputIdentitiesByName:haxe.ds.StringMap<Array<String>>;
	final canonicalIdentity:String;

	public function new(decisions:Array<CompilerConditionalDecision>) {
		this.decisions = decisions == null ? [] : decisions.copy();
		inputIdentitiesByName = new haxe.ds.StringMap<Array<String>>();
		final revisionByAccess = new haxe.ds.StringMap<String>();
		final values = new Array<Null<String>>();
		values.push("conditional-compilation-observation-v1");
		for (decision in this.decisions) {
			if (decision == null)
				throw "conditional-compilation observation contains a null decision";
			values.push(decision.getCanonicalIdentity());
			for (input in decision.getInputs()) {
				final previousRevision = revisionByAccess.get(input.accessKey());
				if (previousRevision != null && previousRevision != input.getObservedInputRevision())
					throw "conditional-compilation observation contains conflicting observations for definition: " + input.name;
				revisionByAccess.set(input.accessKey(), input.getObservedInputRevision());
				var identities = inputIdentitiesByName.get(input.name);
				if (identities == null) {
					identities = [];
					inputIdentitiesByName.set(input.name, identities);
				}
				if (identities.indexOf(input.canonicalKey()) < 0)
					identities.push(input.canonicalKey());
			}
		}
		for (identities in inputIdentitiesByName)
			identities.sort(compareText);
		canonicalIdentity = CompilerCacheIdentity.encode(values);
	}

	public static function empty():CompilerConditionalCompilationObservation
		return new CompilerConditionalCompilationObservation([]);

	public function getCanonicalIdentity():String
		return canonicalIdentity;

	public function getObservedDefineNames():Array<String> {
		final names = [for (name in inputIdentitiesByName.keys()) name];
		names.sort(compareText);
		return names;
	}

	/** Return changed key names in canonical order without exposing either value. **/
	public function changedDefineNames(previous:CompilerConditionalCompilationObservation):Array<String> {
		final names = new haxe.ds.StringMap<Bool>();
		for (name in inputIdentitiesByName.keys())
			names.set(name, true);
		if (previous != null)
			for (name in previous.inputIdentitiesByName.keys())
				names.set(name, true);
		final changed = new Array<String>();
		for (name in names.keys()) {
			final before = previous == null ? null : previous.inputIdentitiesByName.get(name);
			final after = inputIdentitiesByName.get(name);
			if (!sameIdentities(before, after))
				changed.push(name);
		}
		changed.sort(compareText);
		return changed;
	}

	static function sameIdentities(left:Null<Array<String>>, right:Null<Array<String>>):Bool {
		if (left == null || right == null)
			return left == right;
		if (left.length != right.length)
			return false;
		for (index in 0...left.length)
			if (left[index] != right[index])
				return false;
		return true;
	}

	static function compareText(left:String, right:String):Int
		return left < right ? -1 : (left > right ? 1 : 0);
}
