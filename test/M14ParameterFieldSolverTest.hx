import TyInferenceTerm;

/** Open input records share field constraints without leaking failed speculation or fabricating types. */
class M14ParameterFieldSolverTest {
	static function check(value:Bool, message:String):Void {
		if (!value)
			throw message;
	}

	static function rejects(action:Void->Void, expected:String):Void {
		var rejected = false;
		try
			action()
		catch (message:String)
			rejected = message.indexOf(expected) >= 0;
		check(rejected, 'missing rejection: ' + expected);
	}

	static function main():Void {
		final intType = TyType.fromHintText('Int');
		final stringType = TyType.fromHintText('String');
		final solver = new TyInferenceSolver('parameter-fields');
		final input = solver.freshOmittedParameter();
		final alias = solver.freshOmittedParameter();
		final first = solver.field(input, 'first');
		check(solver.constrain(first, Known(intType)), 'first field was not constrained');
		check(solver.constrain(alias, input), 'parameter alias failed');
		check(solver.constrain(solver.field(alias, 'second'), Known(stringType)), 'alias field failed');
		check(solver.preview(input).getSemanticKey() == TyType.anonymous(['first', 'second'], [intType, stringType]).getSemanticKey(),
			'alias lost field requirements');
		check(!solver.constrain(first, Known(stringType)), 'conflicting field accepted');
		check(solver.requireSolved(first).getSemanticKey() == 'primitive:Int', 'failed constraint changed a field');
		final candidate = solver.fork();
		candidate.field(input, 'discarded');
		check(solver.preview(input).getAnonymousFieldNames().indexOf('discarded') < 0, 'fork field leaked');
		final nested = solver.field(input, 'nested');
		check(solver.constrain(solver.field(nested, 'length'), Known(intType)), 'nested field failed');
		check(!solver.constrain(input, nested), 'recursive input record accepted');
		final foreign = new TyInferenceSolver('foreign');
		rejects(() -> solver.field(foreign.fresh(), 'field'), 'another owner');
		final closed = TyInferenceSolver.fromType(TyType.anonymous(['first'], [intType]));
		check(solver.field(closed, 'missing') == null, 'closed record grew a field');
		final unused = solver.freshOmittedParameter();
		final partiallyKnown = solver.freshOmittedParameter();
		solver.field(partiallyKnown, 'unresolved');
		solver.seal();
		check(solver.published(unused).isUnknown(), 'unused input became a fabricated type');
		check(solver.published(partiallyKnown).getAnonymousFieldTypes()[0].isUnknown(), 'unconstrained field became a fabricated type');
		rejects(() -> solver.requireSolved(unused), 'remains unsolved');
		rejects(() -> solver.field(input, 'late'), 'absent from sealed');
		for (reverse in [false, true]) {
			final required = new TyInferenceSolver('required-parameter-field');
			final concrete = required.fresh();
			final omitted = required.freshOmittedParameter();
			final pending = required.field(omitted, 'value');
			check(reverse ? required.constrain(omitted, concrete) : required.constrain(concrete, omitted), 'required alias failed');
			rejects(() -> required.seal(), 'remains unsolved');
			check(required.constrain(pending, Known(intType)), 'failed seal changed mutable state');
			required.seal();
			check(required.requireSolved(concrete).getSemanticKey() == TyType.anonymous(['value'], [intType]).getSemanticKey(),
				'required record publication differs');
		}
		Sys.println('PARAMETER_FIELD_SOLVER:PASS');
	}
}
