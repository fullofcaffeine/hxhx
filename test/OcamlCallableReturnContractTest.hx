import reflaxe.ocaml.lowered.OcamlCallableReturnContract;
import reflaxe.ocaml.lowered.OcamlCallableReturnContract.OcamlCallableInvocationReference;
import reflaxe.ocaml.lowered.OcamlCallableReturnContract.OcamlCallableReturnBoundary;
import reflaxe.ocaml.lowered.OcamlCallableReturnContract.OcamlCallableReturnInput;
import reflaxe.ocaml.lowered.OcamlCallableViewRepresentation.describe;
import reflaxe.ocaml.lowered.OcamlGenericCallConversion.OcamlGenericValueShape;
import reflaxe.ocaml.lowered.OcamlFunctionPlanBinding;

/** Checks which returned values create identity and which must retain an existing identity. */
class OcamlCallableReturnContractTest {
	static final scalar = FunctionValue([Integer], Integer);
	static final binding:OcamlFunctionPlanBinding = {
		functionId: "return-contract:factory",
		programRevision: "return-contract-program",
		bodyRevision: "return-contract-body",
		pipelineRevision: "return-contract-pipeline"
	};

	static function boundary(name:String, shape:OcamlGenericValueShape):OcamlCallableReturnBoundary {
		return {
			calleeId: name,
			layout: describe(shape),
			programRevision: binding.programRevision,
			pipelineRevision: binding.pipelineRevision,
			functionId: binding.functionId,
			bodyRevision: binding.bodyRevision
		};
	}

	static function rejected(action:Void->Void):Void {
		try {
			action();
		} catch (error:haxe.Exception) {
			if (StringTools.startsWith(error.message, "reflaxe.ocaml [ocaml-callable-"))
				return;
			throw error;
		}
		throw "invalid callback return was accepted";
	}

	static function main():Void {
		final factory = boundary("factory", FunctionValue([], scalar));
		final source:reflaxe.ocaml.lowered.OcamlLoweredOrigin.OcamlLoweredSourceSpan = {file: "Callback.hx", min: 10, max: 20};
		final literal = seal({
			binding: binding,
			boundary: factory,
			ordinal: 0,
			source: source,
			input: Producer(FreshLiteral, describe(scalar))
		});
		if (operation(literal).origin != FreshLiteral)
			throw "literal return lost its allocation policy";
		final forwarded = seal({
			binding: binding,
			boundary: factory,
			ordinal: 1,
			source: source,
			input: CallResult("call:0", factory)
		});
		if (operation(forwarded).origin != null)
			throw "forwarding a call result allocated another identity";
		final preserve = boundary("preserve", FunctionValue([scalar], scalar));
		final parameter = seal({
			binding: binding,
			boundary: preserve,
			ordinal: 0,
			source: source,
			input: Parameter(0)
		});
		if (operation(parameter).origin != null)
			throw "returning a parameter allocated another identity";
		rejected(() -> seal({
			binding: binding,
			boundary: preserve,
			ordinal: 0,
			source: source,
			input: Parameter(1)
		}));
		rejected(() -> seal({
			binding: binding,
			boundary: factory,
			ordinal: 0,
			source: source,
			input: Parameter(0)
		}));
		final scalarResult = boundary("ordinary", FunctionValue([], Integer));
		rejected(() -> seal({
			binding: binding,
			boundary: factory,
			ordinal: 0,
			source: source,
			input: CallResult("call:0", scalarResult)
		}));
		final foreign:OcamlCallableInvocationReference = {
			calleeId: factory.calleeId,
			layout: factory.layout,
			programRevision: "different-program",
			pipelineRevision: factory.pipelineRevision
		};
		rejected(() -> seal({
			binding: binding,
			boundary: factory,
			ordinal: 0,
			source: source,
			input: CallResult("call:0", foreign)
		}));
		rejected(() -> seal({
			binding: binding,
			boundary: factory,
			ordinal: 0,
			source: source,
			input: CallResult("", factory)
		}));
		final higher = FunctionValue([scalar], scalar);
		final higherFactory = boundary("higherFactory", FunctionValue([], higher));
		rejected(() -> seal({
			binding: binding,
			boundary: higherFactory,
			ordinal: 0,
			source: source,
			input: Producer(FreshLiteral, describe(higher))
		}));
		final incompatible = FunctionValue([Text(false)], Integer);
		rejected(() -> seal({
			binding: binding,
			boundary: factory,
			ordinal: 0,
			source: source,
			input: Producer(FreshLiteral, describe(incompatible))
		}));
		rejected(() -> requireBinding(literal, {
			functionId: binding.functionId,
			programRevision: binding.programRevision,
			bodyRevision: "changed-body",
			pipelineRevision: binding.pipelineRevision
		}));
		// Two synthetic returns can share a source span. Their structural ordinals
		// must still give them separate ownership and runtime-helper occurrences.
		final second = seal({
			binding: binding,
			boundary: factory,
			ordinal: 1,
			source: source,
			input: Producer(FreshLiteral, describe(scalar))
		});
		if (literal.id == second.id)
			throw "two return occurrences shared one identity";
		final wrongBody:OcamlCallableReturnBoundary = {
			calleeId: factory.calleeId,
			layout: factory.layout,
			programRevision: factory.programRevision,
			pipelineRevision: factory.pipelineRevision,
			functionId: factory.functionId,
			bodyRevision: "another-body"
		};
		rejected(() -> seal({
			binding: binding,
			boundary: wrongBody,
			ordinal: 0,
			source: source,
			input: Producer(FreshLiteral, describe(scalar))
		}));
		final dynamicCallback = FunctionValue([DynamicValue], DynamicValue);
		final boolCallback = FunctionValue([Boolean], Boolean);
		final boolBoundary = boundary("boolAdapter", FunctionValue([dynamicCallback], boolCallback));
		final boolReturn = seal({
			binding: binding,
			boundary: boolBoundary,
			ordinal: 0,
			source: source,
			input: Parameter(0)
		});
		final boolOperation = operation(boolReturn);
		if (Std.string(boolOperation.conversion) != "AdaptFunction([BoxBoolean],UnboxBoolean)")
			throw "return adapter reversed its argument or result conversion";
		final uses = reflaxe.ocaml.lowered.OcamlCallableViewRuntime.valueOccurrences(boolOperation);
		if (uses.map(use -> use.role).join(",") != "callback-return/argument:0,callback-return/result"
			|| Lambda.exists(uses, use -> use.ownerId != boolReturn.id))
			throw "Boolean return adapter borrowed another operation's runtime helpers";
		rejected(() -> requireDecision({
			binding: literal.binding,
			boundary: literal.boundary,
			ordinal: 1,
			source: literal.source,
			input: literal.input,
			id: literal.id,
			revision: literal.revision
		}));
		rejected(() -> requireDecision({
			binding: literal.binding,
			boundary: literal.boundary,
			ordinal: literal.ordinal,
			source: literal.source,
			input: CallResult("call:0", factory),
			id: literal.id,
			revision: literal.revision
		}));
		// A caller retains the descriptor it supplied. Mutating it must not alter
		// the selected return contract or its adapter direction.
		switch (factory.layout.shape) {
			case FunctionValue(arguments, _):
				arguments.push(Integer);
			case _:
				throw "factory lost its invocation shape";
		}
		requireDecision(literal);
		requireDecision(forwarded);
		rejected(() -> seal({
			binding: binding,
			boundary: factory,
			ordinal: 0,
			source: source,
			input: Producer(FreshLiteral, describe(scalar))
		}));
		Sys.println("OCAML_CALLABLE_RETURN_CONTRACT:PASS");
	}
}
