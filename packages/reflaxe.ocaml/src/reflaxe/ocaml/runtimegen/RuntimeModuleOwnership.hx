package reflaxe.ocaml.runtimegen;

typedef RuntimeModuleObservationPartition = {
	final runtimeModules:Array<String>;
	final programModules:Array<String>;
}

/**
	Separates generated-program module references from compatibility-runtime references.

	The OCaml syntax collector intentionally reports qualified names such as `HxArray.get`.
	A name beginning with `Hx` is only a candidate, however: Haxe programs may legitimately
	generate modules with the same prefix. This class resolves those observations from explicit
	program and runtime ownership lists before runtime packaging makes a selection.
**/
class RuntimeModuleOwnership {
	static function compareStrings(left:String, right:String):Int {
		return left < right ? -1 : (left > right ? 1 : 0);
	}

	static function stringSet(values:Array<String>):Map<String, Bool> {
		final out:Map<String, Bool> = [];
		if (values == null)
			return out;
		for (value in values)
			if (value != null && value.length > 0)
				out.set(value, true);
		return out;
	}

	static function sortedKeys(values:Map<String, Bool>):Array<String> {
		final out:Array<String> = [];
		for (value in values.keys())
			out.push(value);
		out.sort(compareStrings);
		return out;
	}

	/**
		Classifies compiler-observed names using declared ownership rather than their prefix.

		Program ownership wins during classification because a generated reference resolves to
		the current program unit. A later collision check rejects the build if runtime selection
		would also link a runtime unit with that name.
	**/
	public static function partitionCompilerObservations(observedModules:Array<String>, programModules:Array<String>,
			runtimeModules:Array<String>):RuntimeModuleObservationPartition {
		final programSet = stringSet(programModules);
		final runtimeSet = stringSet(runtimeModules);
		final observedProgramModules:Map<String, Bool> = [];
		final observedRuntimeModules:Map<String, Bool> = [];
		if (observedModules != null) {
			for (moduleName in observedModules) {
				if (moduleName == null || moduleName.length == 0)
					continue;
				if (programSet.exists(moduleName)) {
					observedProgramModules.set(moduleName, true);
				} else if (runtimeSet.exists(moduleName)) {
					observedRuntimeModules.set(moduleName, true);
				} else {
					throw 'Unknown OCaml runtime module "$moduleName" requested by compiler-observed generated output.';
				}
			}
		}
		return {
			runtimeModules: sortedKeys(observedRuntimeModules),
			programModules: sortedKeys(observedProgramModules)
		};
	}

	/** Rejects target-unit collisions only when the conflicting runtime unit is selected. **/
	public static function assertNoSelectedRuntimeCollisions(programModules:Array<String>, selectedRuntimeModules:Array<String>):Void {
		final programSet = stringSet(programModules);
		final collisions:Map<String, Bool> = [];
		if (selectedRuntimeModules != null)
			for (moduleName in selectedRuntimeModules)
				if (moduleName != null && programSet.exists(moduleName))
					collisions.set(moduleName, true);
		final sortedCollisions = sortedKeys(collisions);
		if (sortedCollisions.length == 0)
			return;
		throw "OCaml module ownership collision: the generated Haxe program and the selected reflaxe.ocaml runtime both provide "
			+ sortedCollisions.join(", ")
			+ ". Rename the Haxe module or compile generated program modules with -D ocaml_module_prefix=<prefix>.";
	}
}
