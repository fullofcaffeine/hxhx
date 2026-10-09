import haxe.ds.StringMap;
import TypedExpr.TypedExprTag;
import TyCallAlignment.TyCallArgumentSlot;

/** Receiver writers retain caller storage; other required calls may save a receiver value. */
private typedef RequiredInlineSelection = {
	final calls:StringMap<Bool>;
	final writers:StringMap<Bool>;
};

/**
	Expands calls whose Haxe bodies cannot be replaced by ordinary target calls.

	Extern inline methods require their authored body at each call, including
	null-safe instance methods on ordinary classes. Abstract methods
	that replace `this` must write to the caller's backing storage. Multi-type
	abstract methods also need their authored bodies because the
	selected provider does not own abstract-only methods. These calls use one
	body expansion, with exact declaration and local identities.

	Ordinary instance receivers are saved once before arguments, without a null
	check. Abstract writers retain the caller's storage expression. Arguments are
	saved before the body, while writes happen at their original statement, even
	before a throw. A continuation through conditional branches turns helper
	returns into invocation results without introducing another callable or
	changing the caller's return destination. Unsupported body forms fail here;
	targets must never guess a receiver-reference convention.
 */
class TypedRequiredInlineLowering {
	final helpers:StringMap<TypedFunction>;
	final selected:StringMap<Bool>;
	final writers:StringMap<Bool>;
	final allocator:TyCompilerTemporaryAllocator;
	final active:Array<String> = [];
	final semanticIndex:TyperIndex;
	final ownerIdentity:String;
	var loopOrdinal:Int = 0;
	var loopTargets:StringMap<TyControlTarget> = new StringMap();
	var typeBindings:StringMap<TyType> = new StringMap();

	function new(helpers:StringMap<TypedFunction>, selected:RequiredInlineSelection, owner:String, index:TyperIndex) {
		this.helpers = helpers;
		this.selected = selected.calls;
		this.writers = selected.writers;
		semanticIndex = index;
		ownerIdentity = owner;
		allocator = new TyCompilerTemporaryAllocator(owner, "abstract-receiver-v1", "__hxhx_inline_receiver_");
	}

	static function key(declaration:TyDeclarationInfo):String
		return declaration.getIdentity().getCanonicalKey();

	/** Extern authority may come from the method itself or its declaring class. */
	static function isExtern(declaration:TyDeclarationInfo, index:TyperIndex):Bool {
		if (declaration.getIsExtern())
			return true;
		final owner = index.getByFullName(declaration.getOwner().getCanonicalName());
		return Std.isOfType(owner, TyClassInfo) && (cast owner : TyClassInfo).getIsExtern();
	}

	static function voidType():TyType
		return TyType.fromHintText("Void");

	/** An implicit abstract call keeps its abstract owner even though explicit this reads expose backing storage. */
	function usesImplicitReceiver(callee:TypedExpr, declaration:TyDeclarationInfo):Bool {
		if (callee.getTag() == NameRead)
			return true;
		final owner = semanticIndex.getAbstractByFullName(declaration.getOwner().getCanonicalName());
		return owner != null
			&& owner.getMultiTypePolicy() != null
			&& callee.getTag() == FieldRead
			&& callee.getExpressions().length == 1
			&& callee.getExpressions()[0].getTag() == ThisValue;
	}

	static function reads(binding:TyLocalBinding, position:Null<HxPos>):TypedExpr
		return TypedExpr.localRead(binding.getSourceName(), binding.getType(), position, binding);

	/** Save a parameter or declared local using its instantiated contract, including an actual runtime conversion when required. */
	function storedValue(value:TypedExpr, declared:TyType):TypedExpr {
		final expected = TyTypeSubstitution.apply(declared, typeBindings);
		final conversion = TyImplicitConversionPlan.select(semanticIndex, expected, value.getType());
		if (conversion != null)
			return conversion.apply(value);
		// Call selection already proves this core enum relationship. Saving an
		// inline parameter must preserve the same enum object and its source type.
		if (TyEnumValueCompatibility.accepts(semanticIndex, expected, value.getType()))
			return TypedExpr.castValue(value, "", expected, value.getPosition(), true);
		// Ordinary assignment also admits Dynamic inputs and compatible nullable
		// views. Preserve both types for target storage without adding a runtime
		// checked cast or treating an unresolved relationship as permission.
		if (TyAssignmentCompatibility.classify(expected, value.getType(), Unchecked) == Compatible)
			return TypedExpr.castValue(value, "", expected, value.getPosition());
		throw "inline storage requires a proven conversion from " + value.getType().getSemanticKey() + " to " + expected.getSemanticKey()
			+ " while expanding " + active.join(" -> ");
	}

	/** Detect direct rebinding and calls to already-selected helpers to a fixed point. */
	static function needsExpression(expression:TypedExpr, selected:StringMap<Bool>):Bool {
		final children = expression.getExpressions();
		final updatingUnary = expression.getTag() == Unary
			&& (expression.getUnaryOperator() == HxUnaryOperator.Increment || expression.getUnaryOperator() == HxUnaryOperator.Decrement);
		if ((expression.getTag() == Assign || expression.getTag() == CompoundAssign || updatingUnary)
			&& children.length > 0
			&& children[0].getTag() == ThisValue)
			return true;
		final declaration = expression.getDeclaration();
		if (expression.getTag() == Call && declaration != null && !declaration.getIsStatic() && selected.exists(key(declaration)))
			return true;
		for (child in children)
			if (needsExpression(child, selected))
				return true;
		return false;
	}

	static function needsStatement(statement:TypedStmt, selected:StringMap<Bool>):Bool {
		for (expression in statement.getExpressions())
			if (needsExpression(expression, selected))
				return true;
		for (child in statement.getStatements())
			if (needsStatement(child, selected))
				return true;
		return false;
	}

	/** Source locals and earlier compiler temporaries both receive fresh caller-owned identities. */
	function substitute(expression:TypedExpr, receiver:Null<TypedExpr>, locals:StringMap<TyLocalBinding>):TypedExpr {
		final children = expression.getExpressions();
		switch expression.getTag() {
			case ThisValue:
				if (receiver == null)
					throw "static inline body cannot read an instance receiver";
				return receiver.withType(TyTypeSubstitution.apply(expression.getType(), typeBindings));
			case NameRead if (expression.getFieldInfo() != null && !expression.getFieldInfo().getIsStatic()):
				if (receiver == null)
					throw "static inline body cannot read an instance field";
				// Bare field syntax belongs to the helper's receiver, never the caller's this.
				final access = TypedExpr.fieldRead(receiver, expression.getTexts()[0], TyTypeSubstitution.apply(expression.getType(), typeBindings),
					expression.getPosition(), expression.getFieldInfo());
				return expression.getHasPropertyStorageAccess() ? access.withPropertyStorageAccess() : access;
			case LocalRead:
				final bindings = expression.getLocalBindings();
				if (bindings.length != 1 || !locals.exists(bindings[0].getIdentity().getCanonicalKey()))
					throw "required inline body lost its exact local binding";
				return reads(locals.get(bindings[0].getIdentity().getCanonicalKey()), expression.getPosition());
			case Temporary:
				final bindings = expression.getLocalBindings();
				if (bindings.length != 1 || children.length != 1)
					throw "required inline temporary lacks its declaration";
				final initial = substitute(children[0], receiver, locals);
				final binding = allocator.allocate("temporary", initial.getType());
				locals.set(bindings[0].getIdentity().getCanonicalKey(), binding);
				return TypedExpr.temporary(binding.getSourceName(), binding.getType().getDisplay(), initial, voidType(), expression.getPosition(), binding);
			case Lambda | SourceFunction | ReturnExpr:
				throw "required inline requires explicit nested callable or expression return ownership";
			case _:
		}
		final rewritten = [for (child in children) substitute(child, receiver, locals)];
		if (expression.getTag() == NewValue && expression.getConstructorApplication() != null) {
			final application = expression.getConstructorApplication().specialize(semanticIndex, typeBindings, children, rewritten);
			return TypedExpr.newValue(application.getConstructedType().getCanonicalDisplay(), rewritten, application.getConstructedType(),
				expression.getPosition(), application);
		}
		final declaration = expression.getDeclaration();
		if (expression.getTag() == Call
			&& declaration != null
			&& !declaration.getIsStatic()
			&& usesImplicitReceiver(children[0], declaration)) {
			if (receiver == null)
				throw "static inline body cannot call an implicit instance method";
			rewritten[0] = TypedExpr.fieldRead(receiver, declaration.getSignature().getName(), children[0].getType(), children[0].getPosition());
		}
		try {
			return expand(expression.withInlineTypes(rewritten, typeBindings));
		} catch (error:haxe.Exception) {
			throw error.message + " while expanding " + active.join(" -> ") + " at " + Std.string(expression.getTag())
				+ (declaration == null ? "" : " " + key(declaration));
		}
	}

	/** A branch consumes the remaining helper statements only when it has not returned or thrown. */
	static function hasReturn(statement:TypedStmt):Bool {
		if (statement.getTag() == Return || statement.getTag() == ReturnVoid)
			return true;
		for (child in statement.getStatements())
			if (hasReturn(child))
				return true;
		return false;
	}

	/** Each expansion gets caller-owned loop destinations; nested jumps retain the selected loop. */
	function introduceLoop(statement:TypedStmt):TyControlTarget {
		final source = statement.getControlTarget();
		if (source == null || source.getKind() != Loop)
			throw "required inline loop lacks its selected source destination";
		final parent = source.getParent();
		final target = new TyControlTarget({
			ownerIdentity: ownerIdentity,
			sourceRevision: "required-inline-loops-v1",
			ordinal: loopOrdinal++,
			kind: Loop,
			sourceIdentity: source.getCanonicalIdentity(),
			parent: parent == null ? null : loopTargets.get(parent.getCanonicalIdentity())
		});
		loopTargets.set(source.getCanonicalIdentity(), target);
		return target;
	}

	function selectedLoop(statement:TypedStmt):TyControlTarget {
		final source = statement.getControlTarget();
		final target = source == null ? null : loopTargets.get(source.getCanonicalIdentity());
		if (target == null)
			throw "required inline jump lost its selected loop destination";
		return target;
	}

	/** Keep ordinary conditional effects linear; distribute the continuation only around helper returns. */
	function body(statements:Array<TypedStmt>, receiver:Null<TypedExpr>, locals:StringMap<TyLocalBinding>, resultType:TyType):TypedExpr {
		final output = new Array<TypedExpr>();
		for (index in 0...statements.length) {
			final statement = statements[index];
			final values = statement.getExpressions();
			final children = statement.getStatements();
			final position = statement.getPosition();
			switch statement.getTag() {
				case Expression:
					output.push(substitute(values[0], receiver, locals));
				case Var:
					final bindings = statement.getLocalBindings();
					if (bindings.length != 1 || values.length != 1 || statement.getMetadata().length != 0)
						throw "required inline local requires one initialized exact binding";
					final initial = storedValue(substitute(values[0], receiver, locals), bindings[0].getType());
					final binding = allocator.allocate("local", initial.getType());
					locals.set(bindings[0].getIdentity().getCanonicalKey(), binding);
					output.push(TypedExpr.temporary(binding.getSourceName(), binding.getType().getDisplay(), initial, voidType(), position, binding));
				case Return:
					output.push(substitute(values[0], receiver, locals));
					return TypedExpr.block(output, resultType, position);
				case ReturnVoid:
					if (!resultType.isVoid())
						throw "required inline returned no required value";
					output.push(TypedExpr.block([], voidType(), position));
					return TypedExpr.block(output, resultType, position);
				case Throw:
					output.push(TypedExpr.throwExpr(substitute(values[0], receiver, locals), position));
					return TypedExpr.block(output, resultType, position);
				case Block:
					output.push(body(children.concat(statements.slice(index + 1)), receiver, locals.copy(), resultType));
					return TypedExpr.block(output, resultType, position);
				case If:
					final condition = substitute(values[0], receiver, locals);
					if (!hasReturn(statement)) {
						final yes = body([children[0]], receiver, locals.copy(), voidType());
						final no = children.length == 2 ? body([children[1]], receiver, locals.copy(), voidType()) : null;
						output.push(TypedExpr.sourceIf(condition, yes, no, voidType(), position));
						continue;
					}
					final remaining = statements.slice(index + 1);
					final yes = body([children[0]].concat(remaining), receiver, locals.copy(), resultType);
					final no = body((children.length == 2 ? [children[1]] : []).concat(remaining), receiver, locals.copy(), resultType);
					output.push(TypedExpr.sourceIf(condition, yes, no, resultType, position));
					return TypedExpr.block(output, resultType, position);
				case ForIn | ForKeyValue | While | DoWhile:
					if (hasReturn(statement))
						throw "Cannot inline a not final return while expanding " + active.join(" -> ");
					final target = introduceLoop(statement);
					final loopLocals = locals.copy();
					// The iterable and condition see the enclosing scope, before new iteration bindings.
					final input = substitute(values[0], receiver, locals);
					final bindings = [
						for (binding in statement.getLocalBindings()) {
							final fresh = allocator.allocate("iteration", TyTypeSubstitution.apply(binding.getType(), typeBindings));
							loopLocals.set(binding.getIdentity().getCanonicalKey(), fresh);
							fresh;
						}
					];
					final loopBody = body(children, receiver, loopLocals, voidType());
					output.push(statement.getTag() == ForIn
						|| statement.getTag() == ForKeyValue ? TypedExpr.sourceFor(HxForBinding.fromNames(bindings.map(binding -> binding.getSourceName())),
							input, loopBody, voidType(), position, bindings,
							target) : TypedExpr.whileExpr(input, [loopBody], true, voidType(), position, statement.getTag() == DoWhile ? DoWhile : Normal)
							.withControlTarget(target));
				case Break | Continue:
					output.push((statement.getTag() == Break ? TypedExpr.breakExpr(position) : TypedExpr.continueExpr(position))
						.withControlTarget(selectedLoop(statement)));
					return TypedExpr.block(output, TyType.noNormalCompletion(), position);
				case _:
					throw "required inline requires shared support for statement " + Std.string(statement.getTag()) + " while expanding " + active.join(" -> ");
			}
		}
		if (!resultType.isVoid())
			throw "required inline can complete without its required result";
		output.push(TypedExpr.block([], voidType(), null));
		return TypedExpr.block(output, resultType, null);
	}

	/** Static extern calls have no runtime receiver; abstract writers retain their caller's storage. */
	function expand(expression:TypedExpr):TypedExpr {
		final declaration = expression.getDeclaration();
		if (expression.getTag() != Call || declaration == null || !selected.exists(key(declaration)))
			return expression;
		final identity = key(declaration);
		if (active.contains(identity) || active.length >= 64)
			throw "recursive required inline expansion: " + identity;
		final helper = helpers.get(identity);
		final environment = helper.getEnvironment();
		final children = expression.getExpressions();
		final callee = children[0];
		if (environment == null)
			throw "required inline call requires its exact environment: " + identity;
		var receiver:Null<TypedExpr> = null;
		final prefix = new Array<TypedExpr>();
		final abstractOwner = semanticIndex.getAbstractByFullName(declaration.getOwner().getCanonicalName());
		final multiType = !declaration.getIsStatic() && abstractOwner != null && abstractOwner.getMultiTypePolicy() != null;
		var ownerBindings = new StringMap<TyType>();
		if (!declaration.getIsStatic()) {
			if (callee.getTag() != FieldRead || callee.getExpressions().length != 1)
				throw "required inline call requires its exact receiver: " + identity;
			receiver = callee.getExpressions()[0];
			if (abstractOwner == null) {
				final owner = semanticIndex.getByFullName(declaration.getOwner().getCanonicalName());
				final bindings = TyNominalApplication.receiverBindings(semanticIndex, owner, receiver.getType());
				if (bindings != null)
					ownerBindings = bindings;
			}
			if (multiType) {
				if (receiver.getType().getNominalIdentity() == null
					|| !receiver.getType().getNominalIdentity().equals(abstractOwner.getIdentity()))
					throw "multi-type inline receiver belongs to another applied owner";
				ownerBindings = TyTypeSubstitution.bind(abstractOwner.getTypeParameterIds(), receiver.getType().getTypeArguments(), identity);
			}
			if (abstractOwner == null) {
				// Saving the value preserves null-safe bodies and exactly-once effects.
				// Arguments may mutate the source local after receiver evaluation.
				final stored = allocator.allocate("receiver", receiver.getType());
				prefix.push(TypedExpr.temporary(stored.getSourceName(), stored.getType().getDisplay(), receiver, voidType(), receiver.getPosition(), stored));
				receiver = reads(stored, receiver.getPosition());
			} else if (multiType && !writers.exists(identity)) {
				final backing = TyTypeSubstitution.apply(abstractOwner.getUnderlyingType(), ownerBindings);
				// This abstract already stores the selected provider. Save the receiver
				// before arguments so repeated this reads cannot repeat caller effects.
				final stored = allocator.allocate("receiver", backing);
				prefix.push(TypedExpr.temporary(stored.getSourceName(), backing.getDisplay(),
					TypedExpr.castValue(receiver, "", backing, receiver.getPosition(), true), voidType(), receiver.getPosition(), stored));
				receiver = reads(stored, receiver.getPosition());
			} else
				switch receiver.getTag() {
					case LocalRead | NameRead | FieldRead | ArrayAccess | ThisValue:
					case _:
						throw "inline abstract receiver requires writable caller storage: " + identity;
				}
		}
		final arguments = children.slice(1);
		if (expression.getExtensionProvider() != null) {
			if (!declaration.getIsStatic() || callee.getTag() != FieldRead || callee.getExpressions().length != 1)
				throw "inline extension call requires its resolved receiver argument: " + identity;
			arguments.unshift(callee.getExpressions()[0]);
		}
		final parameters = environment.getParams();
		final named = expression.getNamedArguments();
		if (named == null && arguments.length != parameters.length)
			throw "required inline requires checked argument alignment: " + identity;
		var slots:Array<TyCallArgumentSlot> = named == null ? [for (index in 0...arguments.length) Supplied(index)] : named.getArguments().getSlots();
		if (named != null && expression.getExtensionProvider() != null) {
			slots = [
				for (slot in slots)
					switch slot {
						case Supplied(index):
							Supplied(index + 1);
						case Omitted:
							Omitted;
						case _:
							throw "required inline rest arguments need explicit packing";
					}
			];
			slots.unshift(Supplied(0));
		}
		if (slots.length != parameters.length)
			throw "required inline alignment differs from its exact parameters";
		if (declaration.getTypeParameterIds().length != 0 && named == null)
			throw "generic inline call requires its selected argument signature: " + identity;
		final selectedParameters = named == null ? declaration.getSignature().getArgs().copy() : named.getArguments().getFunctionType().getFunctionArguments();
		if (named != null && expression.getExtensionProvider() != null)
			selectedParameters.unshift(arguments[0].getType());
		final previousBindings = typeBindings;
		final previousLoops = loopTargets;
		loopTargets = new StringMap();
		typeBindings = TyMethodGenericBinding.inlineBindings(declaration, selectedParameters, expression.getType(), semanticIndex);
		for (identity => type in ownerBindings)
			typeBindings.set(identity, type);
		final locals = new StringMap<TyLocalBinding>();
		var consumed = 0;
		for (index in 0...parameters.length) {
			final expected = TyTypeSubstitution.apply(parameters[index].getType(), typeBindings);
			final value = switch slots[index] {
				case Supplied(source):
					if (source != consumed || source >= arguments.length)
						throw "required inline alignment changed source evaluation order";
					consumed++;
					storedValue(arguments[source], parameters[index].getType());
				case Omitted:
					TypedExpr.nullValue(expected, expression.getPosition());
				case _:
					throw "required inline rest arguments need explicit packing";
			};
			if (value.getType().hasUnknownComponent())
				throw "required inline argument requires a complete type";
			final binding = allocator.allocate("argument", value.getType());
			locals.set(parameters[index].getIdentity().getCanonicalKey(), binding);
			prefix.push(TypedExpr.temporary(binding.getSourceName(), binding.getType().getDisplay(), value, voidType(), value.getPosition(), binding));
		}
		if (consumed != arguments.length)
			throw "required inline alignment omitted a source operand";
		active.push(identity);
		// Defaults are conditional entry work after all receiver and argument effects.
		// A supplied null and an omission both select the authored default in Haxe.
		for (value in helper.getDefaults()) {
			final parameter = parameters[value.getParameterIndex()];
			final destination = reads(locals.get(parameter.getIdentity().getCanonicalKey()), expression.getPosition());
			final missing = TypedExpr.binary("==", destination, TypedExpr.nullValue(TyType.fromHintText("Null"), expression.getPosition()),
				TyType.fromHintText("Bool"), expression.getPosition());
			final initial = storedValue(substitute(value.getExpression(), receiver, locals), parameter.getType());
			final assignment = TypedExpr.assign(destination, initial, destination.getType(), expression.getPosition());
			prefix.push(TypedExpr.sourceIf(missing, assignment, null, voidType(), expression.getPosition()));
		}
		prefix.push(body(helper.getBody().getStatements(), receiver, locals, expression.getType()));
		active.pop();
		typeBindings = previousBindings;
		loopTargets = previousLoops;
		return TypedExpr.block(prefix, expression.getType(), expression.getPosition());
	}

	function expression(input:TypedExpr, implicitReceiver:Null<TypedExpr>):TypedExpr {
		final children = [for (child in input.getExpressions()) expression(child, implicitReceiver)];
		final declaration = input.getDeclaration();
		if (input.getTag() == Call
			&& declaration != null
			&& !declaration.getIsStatic()
			&& selected.exists(key(declaration))
			&& usesImplicitReceiver(children[0], declaration)) {
			if (implicitReceiver == null)
				throw "required inline lost its implicit source receiver";
			children[0] = TypedExpr.fieldRead(implicitReceiver, declaration.getSignature().getName(), children[0].getType(), children[0].getPosition());
		}
		return expand(input.withExpressions(children));
	}

	function statement(input:TypedStmt, receiver:Null<TypedExpr>):TypedStmt
		return input.withChildren([for (value in input.getExpressions()) expression(value, receiver)],
			[for (child in input.getStatements()) statement(child, receiver)]);

	static function lower(classes:Array<TypedClass>, index:TyperIndex, helpers:StringMap<TypedFunction>, selected:RequiredInlineSelection):Array<TypedClass> {
		return [
			for (owner in classes) {
				final functions = [
					for (fn in owner.getFunctions()) {
						final pass = new TypedRequiredInlineLowering(helpers, selected, fn.getStableIdentity(), index);
						final abstractInfo = fn.getDeclaration() == null ? null : index.getAbstractByFullName(fn.getDeclaration()
							.getOwner()
							.getCanonicalName());
						final nominal = owner.getSemanticInfo();
						final receiverType = abstractInfo == null ? nominal == null ? null : TyType.nominal(nominal.getIdentity(),
							[
								for (parameter in TyNominalApplication.parameterIds(nominal))
									TyType.typeParameter(parameter)
							]) : abstractInfo.getMultiTypePolicy() == null ? abstractInfo.getUnderlyingType() : TyType.nominal(abstractInfo.getIdentity(), [
								for (parameter in abstractInfo.getTypeParameterIds())
									TyType.typeParameter(parameter)
							]);
						final receiver = receiverType == null ? null : TypedExpr.thisValue(receiverType, null);
						fn.withBody(new TypedFunctionBody([for (item in fn.getBody().getStatements()) pass.statement(item, receiver)],
							fn.getBody().getSourceFingerprint()),
							[
								for (value in fn.getDefaults())
									new TypedFunctionDefault(value.getParameterIndex(), pass.expression(value.getExpression(), receiver))
							]);
					}
				];
				final initializers = [
					for (initializer in owner.getFieldInitializers()) {
						final pass = new TypedRequiredInlineLowering(helpers, selected, initializer.getField().getCanonicalKey(), index);
						new TypedFieldInitializer(initializer.getField(), pass.expression(initializer.getExpression(), null));
					}
				];
				owner.withMembers({functions: functions, fields: owner.getFields(), initializers: initializers});
			}
		];
	}

	static function inventory(classes:Array<TypedClass>, index:TyperIndex, helpers:StringMap<TypedFunction>):Void {
		for (owner in classes)
			for (fn in owner.getFunctions()) {
				final declaration = fn.getDeclaration();
				if (declaration != null
					&& declaration.getIsInline()
					&& declaration.getHasBody()
					&& (isExtern(declaration, index)
						|| (!declaration.getIsStatic() && index.getAbstractByFullName(declaration.getOwner().getCanonicalName()) != null)))
					helpers.set(key(declaration), fn);
			}
	}

	static function select(helpers:StringMap<TypedFunction>, index:TyperIndex):RequiredInlineSelection {
		final selected = new StringMap<Bool>();
		// Every static helper in this inventory is an authored extern inline body.
		for (identity => helper in helpers) {
			final declaration = helper.getDeclaration();
			if (declaration.getIsStatic())
				selected.set(identity, true);
		}
		var changed = true;
		while (changed) {
			changed = false;
			for (identity => helper in helpers)
				if (!selected.exists(identity))
					for (statement in helper.getBody().getStatements())
						if (needsStatement(statement, selected)) {
							selected.set(identity, true);
							changed = true;
							break;
						}
		}
		final calls = selected.copy();
		for (identity => helper in helpers) {
			final owner = index.getAbstractByFullName(helper.getDeclaration().getOwner().getCanonicalName());
			if (isExtern(helper.getDeclaration(), index) || (owner != null && owner.getMultiTypePolicy() != null))
				calls.set(identity, true);
		}
		return {calls: calls, writers: selected};
	}

	public static function lowerClasses(classes:Array<TypedClass>, index:TyperIndex):Array<TypedClass> {
		final helpers = new StringMap<TypedFunction>();
		inventory(classes, index, helpers);
		return lower(classes, index, helpers, select(helpers, index));
	}

	public static function lowerModules(modules:Array<TypedModule>, index:TyperIndex):Array<TypedModule> {
		final helpers = new StringMap<TypedFunction>();
		for (module in modules)
			inventory(module.getTypedClasses(), index, helpers);
		final selected = select(helpers, index);
		return [
			for (module in modules)
				module.withTypedClasses(lower(module.getTypedClasses(), index, helpers, selected))
		];
	}
}
