import TyInferenceTerm.TyInferenceVariable;
import TyInferenceTerm.TyInferenceVariableKind;

/** A read-only declaration lookup projects existing owner terms; it must not allocate inference variables. */
typedef TyInferenceMemberResolver = (TyInferenceTerm, String) -> Null<TyInferenceTerm>;

/**
	Solve generic and omitted-input constraints without mutating published semantic types.
	Each candidate gets a fork. Successful unification is atomic, and committing a
	stale or unrelated candidate fails instead of discarding another constraint.
	Exact unification does not decide implicit conversions or overload preference.
 */
class TyInferenceSolver {
	final owner:String;
	var variables:Array<TyInferenceVariable> = [];
	var solutions:Array<Null<TyInferenceTerm>> = [];
	var dynamicUses:Array<Bool> = [];
	var fieldRequirements:Array<Array<{final name:String; final term:TyInferenceTerm;}>> = [];
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

	/** Only a sealed, solver-owned omitted input can justify a Dynamic value conversion while its annotation stays unresolved. */
	public function isUnresolvedInput(term:TyInferenceTerm):Bool {
		assertOwned(term);
		if (!sealed)
			return false;
		return hasOmittedInputOrigin(term);
	}

	/** Candidate selection may plan a Dynamic conversion from this origin without solving or finalizing the input. */
	public function hasOmittedInputOrigin(term:TyInferenceTerm):Bool {
		assertOwned(term);
		return switch follow(term) {
			case Variable(identity): identity.kind == OmittedInput && preview(term).isUnknown();
			case _: false;
		};
	}

	/** Allocate one distinct omitted argument; spelling and nominal owner do not merge it. */
	public function fresh():TyInferenceTerm {
		return allocate(null);
	}

	/** Empty array elements accept later constraints and default only still-unconstrained elements at seal. */
	public function freshEmptyArrayElement():TyInferenceTerm {
		final term = allocate(null);
		// The empty literal supplies no element evidence. Reuse the deferred
		// fallback mechanism so an unused array can still have a concrete carrier.
		visitDynamicUse(term, false);
		return term;
	}

	/** Only a known method binder may remain open; constructors and ordinary solver variables require concrete solutions. */
	public function freshMethodParameter(parameter:TyTypeParameterId):TyInferenceTerm {
		return allocate(new TyOpenMethodParameterId(owner, variables.length, parameter));
	}

	/** An omitted input may stay unknown; this is missing evidence, never an inferred Dynamic value. */
	public function freshOmittedParameter():TyInferenceTerm {
		return allocate(null, OmittedInput);
	}

	/** An explicitly untyped result accepts later constraints; unused results retain Unknown rather than guessed Dynamic. */
	public function freshUntypedResult():TyInferenceTerm {
		return allocate(null, UntypedResult);
	}

	/** A hint-free cast owns its result constraints independently of its checked operand. */
	public function freshUncheckedCastResult():TyInferenceTerm {
		return allocate(null, UncheckedCastResult);
	}

	/** Only authored cast results and their projected fields may infer a new callable shape. */
	public function isUncheckedCastResult(term:TyInferenceTerm):Bool {
		assertOwned(term);
		return switch term {
			case Variable(identity): identity.kind == UncheckedCastResult;
			case _: false;
		};
	}

	/** Only untyped or hint-free cast results may acquire a callable shape; ordinary unknown inputs remain unproved. */
	public function isInferredCallableResult(term:TyInferenceTerm):Bool {
		assertOwned(term);
		return switch term {
			case Variable(identity): identity.kind == UncheckedCastResult || identity.kind == UntypedResult;
			case _: false;
		};
	}

	/** A call through an untyped or hint-free cast result shares the callable's inferred result variable. */
	public function inferredCallResult(term:TyInferenceTerm):Null<TyInferenceTerm> {
		if (!isInferredCallableResult(term) && !term.match(Function(_, _, _)))
			return null;
		return switch follow(term) {
			case Function(_, result, _): result;
			case _: null;
		};
	}

	/** Keep shared input and result variables when an untyped or cast result becomes callable. */
	public function inferredCallable(term:TyInferenceTerm):TyInferenceTerm {
		return isInferredCallableResult(term) ? follow(term) : term;
	}

	function allocate(openMethodParameter:Null<TyOpenMethodParameterId>, kind:TyInferenceVariableKind = Required):TyInferenceTerm {
		requireMutable();
		final identity = new TyInferenceVariable(owner, variables.length, openMethodParameter, kind);
		variables.push(identity);
		solutions.push(null);
		dynamicUses.push(false);
		fieldRequirements.push([]);
		revision++;
		return Variable(identity);
	}

	/** Preserve structure when an exact expected type contributes a constraint. */
	public static function fromType(type:TyType):TyInferenceTerm {
		if (type.isNullable())
			return Nullable(fromType(type.unwrapNull()));
		if (type.isFunction())
			return Function(type.getFunctionArguments().map(fromType), fromType(type.getFunctionReturn()), type);
		if (type.isAnonymous())
			return Structure(type.getAnonymousFieldTypes().map(fromType), type);
		final identity = type.getNominalIdentity();
		return identity == null ? Known(type) : Nominal(identity, type.getTypeArguments().map(fromType));
	}

	/** Candidate state shares only immutable variable identities and constraint terms. */
	public function fork():TyInferenceSolver {
		requireMutable();
		final candidate = new TyInferenceSolver(owner);
		candidate.variables = variables.copy();
		candidate.dynamicUses = dynamicUses.copy();
		candidate.solutions = [for (solution in solutions) solution == null ? null : copyTerm(solution)];
		candidate.fieldRequirements = [for (fields in fieldRequirements) fields.copy()];
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
		dynamicUses = candidate.dynamicUses.copy();
		solutions = [
			for (solution in candidate.solutions)
				solution == null ? null : copyTerm(solution)
		];
		fieldRequirements = [for (fields in candidate.fieldRequirements) fields.copy()];
		revision++;
	}

	/**
		A field read on an unsolved input adds a requirement to that variable.
		Aliases follow the same variable; forks own independent requirement lists.
		Closed records expose only their existing fields and never grow on reads.
	 */
	public function field(term:TyInferenceTerm, name:String, ?resolveMember:TyInferenceMemberResolver):Null<TyInferenceTerm> {
		assertOwned(term);
		return switch follow(term) {
			case Variable(identity):
				final fields = fieldRequirements[identity.ordinal];
				for (entry in fields)
					if (entry.name == name)
						return entry.term;
				if (sealed)
					throw "field requirement is absent from sealed inference";
				final child = allocate(null, identity.kind);
				fields.push({name: name, term: child});
				child;
			case Structure(fields, signature):
				final ordinal = signature.getAnonymousFieldNames().indexOf(name);
				ordinal < 0 ? null : fields[ordinal];
			case Nullable(inner): field(inner, name, resolveMember);
			case Nominal(_, _) if (resolveMember != null):
				final projected = resolveMember(follow(term), name);
				if (projected != null)
					assertOwned(projected);
				projected;
			case _: null;
		};
	}

	/** Failure never retains a binding made while checking an earlier component. */
	public function constrain(left:TyInferenceTerm, right:TyInferenceTerm, ?resolveMember:TyInferenceMemberResolver):Bool {
		requireMutable();
		assertOwned(left);
		assertOwned(right);
		final candidate = fork();
		if (!candidate.unify(copyTerm(left), copyTerm(right), resolveMember))
			return false;
		commit(candidate);
		return true;
	}

	/**
		Infer a member input through a nullable destination without removing that
		destination's wrapper. Exact unification remains unchanged. The selected
		call still has to pass assignment and target-carrier validation.
	 */
	public function constrainNullableInput(expected:TyInferenceTerm, actual:TyInferenceTerm):Bool {
		requireMutable();
		assertOwned(expected);
		assertOwned(actual);
		final candidate = fork();
		function constrainInput(left:TyInferenceTerm, right:TyInferenceTerm):Bool {
			return switch [candidate.follow(left), candidate.follow(right)] {
				case [Variable(_), Known(value)] if (value.isDynamic()):
					candidate.observeDynamicUse(left);
					true;
				case [Nullable(inner), Nullable(value)]: constrainInput(inner, value);
				case [Nullable(inner), value]: constrainInput(inner, value);
				case [Nominal(owner, inputs), Nominal(other, values)] if (owner.equals(other) && inputs.length == values.length):
					var accepted = true;
					for (index in 0...inputs.length)
						if (!constrainInput(inputs[index], values[index])) {
							accepted = false;
							break;
						}
					accepted;
				case _: candidate.unify(left, right);
			};
		}
		if (!constrainInput(expected, actual))
			return false;
		commit(candidate);
		return true;
	}

	/**
		Record explicit Dynamic input or destination evidence without solving shared variables.
		A later typed use can still constrain an alias or report a conflict. Only
		seal applies this fallback to remaining holes owned by this solver.
		A bare destination preserves omitted input annotations; explicit Dynamic
		input evidence can still constrain those variables through other calls.
	 */
	public function observeDynamicUse(term:TyInferenceTerm, preserveOmittedInputs:Bool = false):Void {
		requireMutable();
		assertOwned(term);
		visitDynamicUse(term, false, preserveOmittedInputs);
		revision++;
	}

	/**
		Inspect a candidate after its recorded Dynamic uses, without finalizing this
		owner. Call alignment can check that a deferred fallback satisfies a written
		parameter while later expressions still contribute concrete constraints.
		Only solver-owned variables with actual Dynamic evidence receive defaults;
		immutable Unknown values and unrelated open variables remain unproved.
	 */
	public function previewDynamicUses(term:TyInferenceTerm):TyType {
		assertOwned(term);
		if (sealed)
			return published(term);
		final candidate = fork();
		candidate.applyDynamicUses();
		return candidate.preview(term);
	}

	/** Use the same deferred defaults for speculative observation and final publication. */
	function applyDynamicUses():Void {
		for (index in 0...dynamicUses.length)
			if (dynamicUses[index])
				visitDynamicUse(Variable(variables[index]), true);
	}

	/** Follow final alias solutions and preserve nominal, callable, and required-field structure. */
	function visitDynamicUse(term:TyInferenceTerm, publish:Bool, preserveOmittedInputs:Bool = false):Void {
		switch follow(term) {
			case Variable(identity):
				if (preserveOmittedInputs && identity.kind == OmittedInput)
					return;
				if (!publish) {
					dynamicUses[identity.ordinal] = true;
				} else if (fieldRequirements[identity.ordinal].length > 0) {
					for (field in fieldRequirements[identity.ordinal])
						visitDynamicUse(field.term, true);
				} else {
					solutions[identity.ordinal] = Known(TyType.fromHintText("Dynamic"));
				}
			case Nominal(_, arguments):
				for (argument in arguments)
					visitDynamicUse(argument, publish, preserveOmittedInputs);
			case Nullable(inner):
				visitDynamicUse(inner, publish, preserveOmittedInputs);
			case Function(arguments, result, _):
				for (argument in arguments)
					visitDynamicUse(argument, publish, preserveOmittedInputs);
				visitDynamicUse(result, publish, preserveOmittedInputs);
			case Structure(fields, _):
				for (field in fields)
					visitDynamicUse(field, publish, preserveOmittedInputs);
			case Known(_):
				// Missing concrete type facts are not solver variables and gain no fallback.
		}
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
			case Function(arguments, result, signature):
				if (!signature.isFunction() || signature.getFunctionArguments().length != arguments.length)
					throw "inference callable arguments differ from their signature";
				for (argument in arguments)
					assertOwned(argument);
				assertOwned(result);
			case Structure(fields, signature):
				if (!signature.isAnonymous() || signature.getAnonymousFieldTypes().length != fields.length)
					throw "inference structural fields differ from their signature";
				for (field in fields)
					assertOwned(field);
			case Known(_):
		}
	}

	static function copyTerm(term:TyInferenceTerm):TyInferenceTerm {
		return switch term {
			case Nominal(identity, arguments): Nominal(identity, arguments.map(copyTerm));
			case Nullable(inner): Nullable(copyTerm(inner));
			case Function(arguments, result, signature): Function(arguments.map(copyTerm), copyTerm(result), signature);
			case Structure(fields, signature): Structure(fields.map(copyTerm), signature);
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
			case Variable(other): identity == other || fieldRequirements[other.ordinal].filter(entry -> occurs(identity, entry.term)).length > 0;
			case Nominal(_, arguments): arguments.filter(argument -> occurs(identity, argument)).length > 0;
			case Nullable(inner): occurs(identity, inner);
			case Function(arguments, result, signature): occurs(identity, result) || arguments.filter(argument -> occurs(identity, argument)).length > 0;
			case Structure(fields, _): fields.filter(field -> occurs(identity, field)).length > 0;
			case Known(_): false;
		};
	}

	function unify(left:TyInferenceTerm, right:TyInferenceTerm, ?resolveMember:TyInferenceMemberResolver):Bool {
		final a = follow(left);
		final b = follow(right);
		return switch [a, b] {
			case [Variable(first), Variable(second)] if (first == second): true;
			case [Variable(first), Variable(second)]:
				if (occurs(first, b) || occurs(second, a)) false; else {
					for (entry in fieldRequirements[first.ordinal]) {
						final target = field(b, entry.name, resolveMember);
						if (!unify(entry.term, target, resolveMember))
							return false;
					}
					solutions[first.ordinal] = b;
					fieldRequirements[first.ordinal] = [];
					true;
				}
			case [Variable(identity), value]:
				if (occurs(identity, value)) false; else {
					for (entry in fieldRequirements[identity.ordinal]) {
						final target = field(value, entry.name, resolveMember);
						if (target == null || !unify(entry.term, target, resolveMember))
							return false;
					}
					solutions[identity.ordinal] = copyTerm(value);
					true;
				}
			case [_, Variable(_)]: unify(b, a, resolveMember);
			case [Known(first), Known(second)]: first.getSemanticKey() == second.getSemanticKey();
			case [Nominal(first, firstArguments), Nominal(second, secondArguments)]: first.equals(second) && unifyArguments(firstArguments, secondArguments,
					resolveMember);
			case [Nullable(first), Nullable(second)]: unify(first, second, resolveMember);
			case [
				Function(firstArguments, firstResult, firstSignature),
				Function(secondArguments, secondResult, secondSignature)
			]: matchingCallableRules(firstSignature,
				secondSignature) && unifyArguments(firstArguments, secondArguments, resolveMember) && unify(firstResult, secondResult, resolveMember);
			case [Structure(first, firstSignature), Structure(second, secondSignature)]: matchingStructuralRules(firstSignature,
					secondSignature) && unifyArguments(first, second, resolveMember);
			case _: false;
		};
	}

	/** Exact unification preserves calling rules; assignment variance belongs to call compatibility. */
	static function matchingCallableRules(left:TyType, right:TyType):Bool {
		final first = left.getFunctionParameters();
		final second = right.getFunctionParameters();
		if (first.length != second.length)
			return false;
		for (index in 0...first.length)
			if (first[index].isOptional != second[index].isOptional || first[index].isRest != second[index].isRest)
				return false;
		return true;
	}

	/** Compare field contracts independently of the child types being solved. Assignment remains a separate relation. */
	static function matchingStructuralRules(left:TyType, right:TyType):Bool {
		final first = left.getAnonymousFields();
		final second = right.getAnonymousFields();
		if (first.length != second.length)
			return false;
		for (index in 0...first.length)
			if (TyAnonymousField.semanticKey(TyAnonymousField.withType(first[index],
				TyType.unknown())) != TyAnonymousField.semanticKey(TyAnonymousField.withType(second[index], TyType.unknown())))
				return false;
		return true;
	}

	function unifyArguments(left:Array<TyInferenceTerm>, right:Array<TyInferenceTerm>, ?resolveMember:TyInferenceMemberResolver):Bool {
		if (left.length != right.length)
			return false;
		for (index in 0...left.length)
			if (!unify(left[index], right[index], resolveMember))
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

	/** Sealed omitted inputs retain explicit Unknown leaves; ordinary required variables still need complete evidence. */
	public function published(term:TyInferenceTerm):TyType {
		if (!sealed)
			throw "inference publication requires a sealed owner";
		assertOwned(term);
		return materialize(term, true, true);
	}

	function materialize(term:TyInferenceTerm, complete:Bool, permitOmitted:Bool = false):TyType {
		return switch follow(term) {
			case Variable(identity):
				final fields = fieldRequirements[identity.ordinal];
				if (fields.length > 0)
					return TyType.anonymous(fields.map(entry -> entry.name), fields.map(entry -> materialize(entry.term, complete, permitOmitted)));
				if (complete && !(permitOmitted && identity.allowsUnknown))
					throw "inference variable remains unsolved: " + identity.owner + "#" + identity.ordinal;
				TyType.unknown();
			case Known(type):
				if (complete && !isComplete(type))
					throw "inference cannot publish an incomplete concrete type in " + owner + ": " + type.getSemanticKey();
				type;
			case Nominal(identity, arguments): TyType.nominal(identity, arguments.map(argument -> materialize(argument, complete, permitOmitted)));
			case Nullable(inner): TyType.nullable(materialize(inner, complete, permitOmitted));
			case Function(arguments, result,
				signature): signature.withFunctionTypes(arguments.map(argument -> materialize(argument, complete, permitOmitted)),
					materialize(result, complete, permitOmitted));
			case Structure(fields, signature): signature.withAnonymousTypes(fields.map(field -> materialize(field, complete, permitOmitted)));
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
					for (entry in fieldRequirements[identity.ordinal])
						requireConcrete(entry.term);
				case Nominal(_, arguments):
					for (argument in arguments)
						requireConcrete(argument);
				case Nullable(inner):
					requireConcrete(inner);
				case Function(arguments, result, signature):
					for (argument in arguments)
						requireConcrete(argument);
					requireConcrete(result);
				case Structure(fields, _):
					for (field in fields)
						requireConcrete(field);
				case Known(type):
					if (type.hasOpenMethodParameter())
						throw "required inference cannot publish an open method parameter";
			}
		}
		for (variable in variables)
			if (variable.openMethodParameter == null && !variable.allowsUnknown)
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

	/** Apply Dynamic-use and empty-array defaults after constraints, then publish open methods and admitted unknown inputs. */
	public function seal():Void {
		requireMutable();
		final candidate = fork();
		candidate.applyDynamicUses();
		candidate.publishOpenMethods();
		for (variable in candidate.variables)
			try {
				candidate.materialize(Variable(variable), true, variable.allowsUnknown);
			} catch (message:String) {
				throw message + " while sealing " + variable.owner + "#" + variable.ordinal;
			}
		commit(candidate);
		sealed = true;
		revision++;
	}
}
