import reflaxe.ocaml.lowered.OcamlCallableProgramAdmission.select;
import reflaxe.ocaml.lowered.OcamlCallableProgramAdmission.OcamlCallableProgramCandidate;
import reflaxe.ocaml.lowered.OcamlGenericCallConversion.OcamlGenericValueShape;

/** Both compiler hosts must reject a changed callback interface when any connected consumer cannot use it. */
class OrdinaryCallableProgramAdmissionTest {
	static function candidate(id:String, signature:OcamlGenericValueShape, dependencies:Array<String>, rejected:Bool = false):OcamlCallableProgramCandidate {
		return {
			id: id,
			fieldName: id,
			signature: signature,
			dependencies: dependencies,
			rejected: rejected,
			usesViews: true
		};
	}

	static function expect(candidates:Array<OcamlCallableProgramCandidate>, expected:Array<String>, unresolvedClassValue:Bool = false):Void {
		final selected = select(candidates, unresolvedClassValue).map(method -> method.calleeId);
		if (selected.join(",") != expected.join(","))
			throw "Callback component selection differs: " + selected.join(",");
	}

	static function main():Void {
		final callback = FunctionValue([Integer], Integer);
		final ordinary = FunctionValue([], EffectOnly);
		final factory = FunctionValue([], callback);
		final input = [
			candidate("caller", ordinary, ["factory"]),
			candidate("factory", factory, ["forwarder"]),
			candidate("forwarder", factory, []),
			candidate("isolated", ordinary, [])
		];
		expect(input, ["caller", "factory", "forwarder", "isolated"]);
		// A use discovered after a caller still prevents every connected ABI change.
		final escaped = input.concat([candidate("observer", ordinary, ["forwarder"], true)]);
		expect(escaped, ["isolated"]);
		escaped.reverse();
		expect(escaped, ["isolated"]);
		expect(input, ["caller", "factory", "forwarder", "isolated"]);
		if (input[1].dependencies.length != 1 || input[1].rejected)
			throw "Selection mutated caller-owned graph facts";
		expect(input, ["isolated"], true);
		expect([candidate("unknown", ordinary, ["missing"]), candidate("isolated", ordinary, [])], ["isolated"]);
		final unsupported = candidate("unsupported", ordinary, []);
		final unresolved:OcamlCallableProgramCandidate = {
			id: unsupported.id,
			fieldName: unsupported.fieldName,
			signature: null,
			dependencies: [],
			rejected: false,
			usesViews: true
		};
		expect([candidate("caller", ordinary, ["unsupported"]), unresolved], []);
		Sys.println("ORDINARY_CALLABLE_PROGRAM_ADMISSION:PASS");
	}
}
