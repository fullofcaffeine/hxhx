/**
	Immutable request-wide compiler configuration used by dependency observation.

	The observation records the selected backend target and every normalized
	compiler define. Inputs are sorted and duplicate names must agree, so map
	insertion order cannot change the sealed identity. This is deliberately
	conservative: finer feature, DCE, macro, and target-neutrality rules may later
	reduce invalidations, but missing an input here must never authorize stale
	typed-module reuse.
**/
class CompilerProgramConfigurationObservation {
	final inputs:Array<CompilerProgramConfigurationInput>;
	final inputRevisionByName:haxe.ds.StringMap<String>;
	final canonicalIdentity:String;

	public function new(inputs:Array<CompilerProgramConfigurationInput>) {
		final sorted = inputs == null ? [] : inputs.copy();
		sorted.sort(compareInputs);
		this.inputs = [];
		inputRevisionByName = new haxe.ds.StringMap<String>();
		for (input in sorted) {
			if (input == null)
				throw "compiler configuration observation contains a null input";
			final previous = inputRevisionByName.get(input.name);
			if (previous != null) {
				if (previous != input.getObservedInputRevision())
					throw "compiler configuration observation contains conflicting revisions for input: " + input.name;
				continue;
			}
			inputRevisionByName.set(input.name, input.getObservedInputRevision());
			this.inputs.push(input);
		}
		final values = new Array<Null<String>>();
		values.push("compiler-program-configuration-observation-v1");
		for (input in this.inputs)
			values.push(input.canonicalKey());
		canonicalIdentity = CompilerCacheIdentity.encode(values);
	}

	public static function empty():CompilerProgramConfigurationObservation
		return new CompilerProgramConfigurationObservation([]);

	/**
		Snapshot the backend and normalized define map used by one typed request.

		Only input names and hashed value revisions survive this call. The raw map
		remains request-owned and may be discarded normally.
	**/
	public static function fromTargetAndDefines(targetId:String, defines:haxe.ds.StringMap<String>):CompilerProgramConfigurationObservation {
		final inputs = [CompilerProgramConfigurationInput.fromValue("target", targetId)];
		if (defines != null)
			for (name in defines.keys())
				inputs.push(CompilerProgramConfigurationInput.fromValue("define:" + name, defines.get(name)));
		return new CompilerProgramConfigurationObservation(inputs);
	}

	public function getInputs():Array<CompilerProgramConfigurationInput>
		return inputs.copy();

	public function getCanonicalIdentity():String
		return canonicalIdentity;

	/** Return changed report-safe input names in canonical order. **/
	public function changedInputNames(previous:CompilerProgramConfigurationObservation):Array<String> {
		final names = new haxe.ds.StringMap<Bool>();
		for (name in inputRevisionByName.keys())
			names.set(name, true);
		if (previous != null)
			for (name in previous.inputRevisionByName.keys())
				names.set(name, true);
		final changed = new Array<String>();
		for (name in names.keys()) {
			final before = previous == null ? null : previous.inputRevisionByName.get(name);
			final after = inputRevisionByName.get(name);
			if (before != after)
				changed.push(name);
		}
		changed.sort(compareText);
		return changed;
	}

	static function compareInputs(left:CompilerProgramConfigurationInput, right:CompilerProgramConfigurationInput):Int
		return compareText(left.name, right.name);

	static function compareText(left:String, right:String):Int
		return left < right ? -1 : (left > right ? 1 : 0);
}
