import TyInferenceTerm.TyInferenceVariable;

/**
	Solve temporary generic constraints without mutating published semantic types.
	Each candidate gets a fork. Successful unification is atomic, and committing a
	stale or unrelated candidate fails instead of discarding another constraint.
	Exact unification does not decide implicit conversions or overload preference.
 */
class TyInferenceSolver {
	final owner:String;
	var variables:Array<TyInferenceVariable> = [];
	var solutions:Array<Null<TyInferenceTerm>> = [];
	var parent:Null<TyInferenceSolver> = null;
	var baseRevision:Int = 0;
	var revision:Int = 0;
	var sealed:Bool = false;

	public function new(owner:String) {
		if (owner == null || owner.length == 0)
			throw "inference requires an owning executable";
		this.owner = owner;
	}

	function requireMutable():Void {
		if (sealed)
			throw "inference owner is already sealed";
	}

	public function isSealed():Bool
		return sealed;

	/** Allocate one distinct omitted argument; spelling and nominal owner do not merge it. */
	public function fresh():TyInferenceTerm {
		return allocate(null);
	}

	/** Only a known method binder may remain open; constructors and ordinary solver variables require concrete solutions. */
	public function freshMethodParameter(parameter:TyTypeParameterId):TyInferenceTerm {
		return allocate(new TyOpenMethodParameterId(owner, variables.length, parameter));
	}

	function allocate(openMethodParameter:Null<TyOpenMethodParameterId>):TyInferenceTerm {
		requireMutable();
		final identity = new TyInferenceVariable(owner, variables.length, openMethodParameter);
		variables.push(identity);
		solutions.push(null);
		revision++;
		return Variable(identity);
	}

	/** Preserve structure when an exact expected type contributes a constraint. */
	public static function fromType(type:TyType):TyInferenceTerm {
		if (type.isNullable())
			return Nullable(fromType(type.unwrapNull()));
		if (type.isFunction())
			return Function(type.getFunctionArguments().map(fromType), fromType(type.getFunctionReturn()));
		final identity = type.getNominalIdentity();
		return identity == null ? Known(type) : Nominal(identity, type.getTypeArguments().map(fromType));
	}

	/** Candidate state shares only immutable variable identities and constraint terms. */
	public function fork():TyInferenceSolver {
		requireMutable();
		final candidate = new TyInferenceSolver(owner);
		candidate.variables = variables.copy();
		candidate.solutions = [for (solution in solutions) solution == null ? null : copyTerm(solution)];
		candidate.parent = this;
		candidate.baseRevision = revision;
		return candidate;
	}

	/** Commit only a direct candidate based on the parent's still-current state. */
	public function commit(candidate:TyInferenceSolver):Void {
		requireMutable();
		if (candidate == null || candidate.parent != this || candidate.baseRevision != revision)
			throw "inference candidate is foreign or stale";
		if (candidate.sealed)
			throw "sealed inference candidate cannot replace mutable state";
		variables = candidate.variables.copy();
		solutions = [
			for (solution in candidate.solutions)
				solution == null ? null : copyTerm(solution)
		];
		revision++;
	}

	/** Failure never retains a binding made while checking an earlier component. */
	public function constrain(left:TyInferenceTerm, right:TyInferenceTerm):Bool {
		requireMutable();
		assertOwned(left);
		assertOwned(right);
		final candidate = fork();
		if (!candidate.unify(copyTerm(left), copyTerm(right)))
			return false;
		commit(candidate);
		return true;
	}

	function assertOwned(term:TyInferenceTerm):Void {
		switch term {
			case Variable(identity):
				if (identity.ordinal < 0 || identity.ordinal >= variables.length || variables[identity.ordinal] != identity)
					throw "inference variable belongs to another owner";
			case Nominal(_, arguments):
				for (argument in arguments)
					assertOwned(argument);
			case Nullable(inner):
				assertOwned(inner);
			case Function(arguments, result):
				for (argument in arguments)
					assertOwned(argument);
				assertOwned(result);
			case Known(_):
		}
	}

	static function copyTerm(term:TyInferenceTerm):TyInferenceTerm {
		return switch term {
			case Nominal(identity, arguments): Nominal(identity, arguments.map(copyTerm));
			case Nullable(inner): Nullable(copyTerm(inner));
			case Function(arguments, result): Function(arguments.map(copyTerm), copyTerm(result));
			case Known(_) | Variable(_): term;
		};
	}

	function follow(term:TyInferenceTerm):TyInferenceTerm {
		return switch term {
			case Variable(identity) if (solutions[identity.ordinal] != null): follow(solutions[identity.ordinal]);
			case _: term;
		};
	}

	function occurs(identity:TyInferenceVariable, term:TyInferenceTerm):Bool {
		return switch follow(term) {
			case Variable(other): identity == other;
			case Nominal(_, arguments): arguments.filter(argument -> occurs(identity, argument)).length > 0;
			case Nullable(inner): occurs(identity, inner);
			case Function(arguments, result): occurs(identity, result) || arguments.filter(argument -> occurs(identity, argument)).length > 0;
			case Known(_): false;
		};
	}

	function unify(left:TyInferenceTerm, right:TyInferenceTerm):Bool {
		final a = follow(left);
		final b = follow(right);
		return switch [a, b] {
			case [Variable(first), Variable(second)] if (first == second): true;
			case [Variable(identity), value]:
				if (occurs(identity, value)) false; else {
					solutions[identity.ordinal] = copyTerm(value);
					true;
				}
			case [_, Variable(_)]: unify(b, a);
			case [Known(first), Known(second)]: first.getSemanticKey() == second.getSemanticKey();
			case [Nominal(first, firstArguments), Nominal(second, secondArguments)]: first.equals(second) && unifyArguments(firstArguments, secondArguments);
			case [Nullable(first), Nullable(second)]: unify(first, second);
			case [Function(firstArguments, firstResult), Function(secondArguments, secondResult)]: unifyArguments(firstArguments,
					secondArguments) && unify(firstResult, secondResult);
			case _: false;
		};
	}

	function unifyArguments(left:Array<TyInferenceTerm>, right:Array<TyInferenceTerm>):Bool {
		if (left.length != right.length)
			return false;
		for (index in 0...left.length)
			if (!unify(left[index], right[index]))
				return false;
		return true;
	}

	/** Return a fresh immutable type graph; an unresolved variable is never Dynamic. */
	public function requireSolved(term:TyInferenceTerm):TyType {
		assertOwned(term);
		return materialize(term, true);
	}

	/** Unknown components are temporary candidate evidence, never publication authority. */
	public function preview(term:TyInferenceTerm):TyType {
		assertOwned(term);
		return materialize(term, false);
	}

	function materialize(term:TyInferenceTerm, complete:Bool):TyType {
		return switch follow(term) {
			case Variable(identity):
				if (complete)
					throw "inference variable remains unsolved: " + identity.owner + "#" + identity.ordinal;
				TyType.unknown();
			case Known(type):
				if (complete && !isComplete(type))
					throw "inference cannot publish an incomplete concrete type";
				type;
			case Nominal(identity, arguments): TyType.nominal(identity, arguments.map(argument -> materialize(argument, complete)));
			case Nullable(inner): TyType.nullable(materialize(inner, complete));
			case Function(arguments, result): TyType.functionType(arguments.map(argument -> materialize(argument, complete)), materialize(result, complete));
		};
	}

	/** An unresolved field nested inside a known structural type is still incomplete. */
	static function isComplete(type:TyType):Bool {
		if (type == null || type.isUnknown() || type.isUnresolved())
			return false;
		if (type.isNullable() && !isComplete(type.unwrapNull()))
			return false;
		if (type.isFunction() && !isComplete(type.getFunctionReturn()))
			return false;
		for (child in type.getTypeArguments().concat(type.getFunctionArguments()).concat(type.getAnonymousFieldTypes()))
			if (!isComplete(child))
				return false;
		return true;
	}

	/** Publish permitted open method variables only after protecting every required-concrete dependency. */
	function publishOpenMethods():Void {
		final required = new haxe.ds.IntMap<Bool>();
		function requireConcrete(term:TyInferenceTerm):Void {
			switch follow(term) {
				case Variable(identity):
					required.set(identity.ordinal, true);
				case Nominal(_, arguments):
					for (argument in arguments)
						requireConcrete(argument);
				case Nullable(inner):
					requireConcrete(inner);
				case Function(arguments, result):
					for (argument in arguments)
						requireConcrete(argument);
					requireConcrete(result);
				case Known(type):
					if (type.hasOpenMethodParameter())
						throw "required inference cannot publish an open method parameter";
			}
		}
		for (variable in variables)
			if (variable.openMethodParameter == null)
				requireConcrete(Variable(variable));
		// Choose the earliest admitted identity in an alias group independently
		// of which direction unification used to link the variables.
		final identities = new haxe.ds.IntMap<TyOpenMethodParameterId>();
		for (variable in variables)
			if (variable.openMethodParameter != null)
				switch follow(Variable(variable)) {
					case Variable(root) if (!required.exists(root.ordinal) && !identities.exists(root.ordinal)):
						identities.set(root.ordinal, variable.openMethodParameter);
					case _:
				}
		for (ordinal => identity in identities)
			solutions[ordinal] = Known(TyType.openMethodParameter(identity));
	}

	/** Required variables must be concrete; valid unconstrained method parameters become immutable open types atomically. */
	public function seal():Void {
		requireMutable();
		final candidate = fork();
		candidate.publishOpenMethods();
		for (variable in candidate.variables)
			candidate.requireSolved(Variable(variable));
		commit(candidate);
		sealed = true;
		revision++;
	}
}
