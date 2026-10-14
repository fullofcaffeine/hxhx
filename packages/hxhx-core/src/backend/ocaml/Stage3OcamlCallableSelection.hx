package backend.ocaml;

import reflaxe.ocaml.lowered.OcamlCallableProgramAdmission.OcamlCallableProgramCandidate;
import reflaxe.ocaml.lowered.OcamlCallableProgramAdmission.OcamlCallableMethodSelection;
import reflaxe.ocaml.lowered.OcamlCallableProgramAdmission.needsBoundary;
import reflaxe.ocaml.lowered.OcamlGenericCallConversion.OcamlGenericValueShape;
import reflaxe.ocaml.lowered.OcamlGenericCallConversion.crossing;

/** Native source owners stay private to this scan; the shared target receives only classified relationships. */
private typedef SourceCandidate = {
	final id:String;
	final fieldName:String;
	final owner:String;
	final signature:Null<OcamlGenericValueShape>;
	final functionBody:Null<TypedFunction>;
	final initializer:Null<TypedExpr>;
	final eligible:Bool;
	final dependencies:Array<String>;
	var rejected:Bool;
	var usesViews:Bool;
};

/**
	Classify native typed uses before the shared target selects callback interfaces.

	For example, a factory and all its callers must use the same callback storage.
	A field initializer or unsupported caller prevents that whole group from changing.
	This adapter supplies exact declaration and local identities from native typing.
	The shared target owns signature conversions and connected-method rejection.
	Selection alone does not authorize emitted storage or bind projected occurrences.
**/
function select(modules:Array<TypedModule>):Array<OcamlCallableMethodSelection> {
	final candidates:Map<String, SourceCandidate> = [];
	for (module in modules)
		for (owner in module.getTypedClasses()) {
			final header = owner.getSourceDeclaration();
			final semantic = owner.getSemanticInfo();
			final classInfo = semantic == null ? null : Std.downcast(semantic, TyClassInfo);
			final ordinaryClass = classInfo != null
				&& !classInfo.getIsExtern()
				&& !classInfo.getIsInterface()
				&& classInfo.getTypeParameters().length == 0
				&& !hasMetadata(HxClassDecl.getMetadata(header), "native");
			for (fn in owner.getFunctions()) {
				fn.assertParsedBodyCurrent();
				final declaration = fn.getDeclaration();
				final name = HxFunctionDecl.getName(fn.getSourceDeclaration());
				final eligible = ordinaryClass
					&& declaration != null
					&& declaration.getIsStatic()
					&& declaration.getHasBody()
					&& !declaration.getIsExtern()
					&& !declaration.getIsDynamic()
					&& declaration.getTypeParameters().length == 0
					&& !hasMetadata(declaration.getMetadata(), "native")
					&& name != "__init__"
					&& semantic.staticMethodCandidates(name).length == 1;
				final id = fn.getStableIdentity();
				if (candidates.exists(id))
					throw "OCaml callback selection received a duplicate typed method";
				candidates.set(id, {
					id: id,
					fieldName: name,
					owner: semantic == null ? "" : semantic.getIdentity().getCanonicalName(),
					signature: declaration == null ? null : declarationShape(declaration),
					functionBody: fn,
					initializer: null,
					eligible: eligible,
					dependencies: [],
					rejected: !eligible,
					usesViews: false
				});
			}
			for (initializer in owner.getFieldInitializers()) {
				final field = initializer.getField();
				final id = "initializer:" + field.getCanonicalKey();
				candidates.set(id, {
					id: id,
					fieldName: field.getName(),
					owner: semantic == null ? "" : semantic.getIdentity().getCanonicalName(),
					signature: null,
					functionBody: null,
					initializer: initializer.getExpression(),
					eligible: false,
					dependencies: [],
					rejected: true,
					usesViews: false
				});
			}
		}
	var unresolvedClassValue = false;
	for (candidate in candidates) {
		final scan = new CallableUseScan(candidate, candidates);
		scan.run();
		unresolvedClassValue = unresolvedClassValue || scan.unresolvedClassValue;
	}
	final facts:Array<OcamlCallableProgramCandidate> = [
		for (candidate in candidates)
			{
				id: candidate.id,
				fieldName: candidate.fieldName,
				signature: candidate.signature,
				dependencies: candidate.dependencies,
				rejected: candidate.rejected,
				usesViews: candidate.usesViews
			}
	];
	return reflaxe.ocaml.lowered.OcamlCallableProgramAdmission.select(facts, unresolvedClassValue);
}

/** Map resolved native types to the target's existing callback shapes without inventing unknown or foreign storage. */
function valueShape(type:TyType):Null<OcamlGenericValueShape> {
	function classify(input:TyType, aliases:Array<TyAliasDefinition>):Null<OcamlGenericValueShape> {
		final alias = input.getAliasDefinition();
		if (alias != null) {
			if (aliases.contains(alias))
				return null;
			aliases = aliases.concat([alias]);
		}
		final type = TyAliasExpansion.reveal(input);
		if (type.isFunction()) {
			final arguments:Array<OcamlGenericValueShape> = [];
			for (parameter in type.getFunctionParameters()) {
				final shape = classify(parameter.type, aliases);
				if (parameter.isOptional || parameter.isRest || shape == null || shape == EffectOnly)
					return null;
				arguments.push(shape);
			}
			final resultType = type.getFunctionReturn();
			final result = resultType == null ? null : classify(resultType, aliases);
			return result == null ? null : FunctionValue(arguments, result);
		}
		if (type.isNullable())
			return switch classify(type.unwrapNull(), aliases) {
				case Integer: NullableInteger;
				case Boolean: NullableBoolean;
				case Text(_): Text(true);
				case _: null;
			};
		return switch type.getSemanticKey() {
			case "primitive:Int": Integer;
			case "primitive:Bool": Boolean;
			case "primitive:String": Text(false);
			case "primitive:Void": EffectOnly;
			case "dynamic": DynamicValue;
			case _: null;
		};
	}
	final shape = classify(type, []);
	return shape != null && reflaxe.ocaml.lowered.OcamlCallableViewRepresentation.supportsValue(shape) ? shape : null;
}

/** Optional and rest parameters keep their original calling convention until a separate target plan covers them. */
function declarationShape(declaration:TyDeclarationInfo):Null<OcamlGenericValueShape> {
	final signature = declaration.getSignature();
	if (signature.getArgOptional().contains(true) || signature.getArgRest().contains(true))
		return null;
	return valueShape(TyType.functionType(signature.getArgs(), signature.getReturnType()));
}

private function isFunction(type:TyType):Bool
	return TyAliasExpansion.reveal(type).isFunction();

private function hasMetadata(entries:Array<String>, name:String):Bool {
	for (entry in entries) {
		var clean = StringTools.trim(entry);
		while (StringTools.startsWith(clean, "@") || StringTools.startsWith(clean, ":"))
			clean = clean.substr(1);
		if (clean == name || StringTools.startsWith(clean, name + "("))
			return true;
	}
	return false;
}

/** One source executable classifies uses; nested functions get fresh local sets so callback captures remain unsupported. */
private class CallableUseScan {
	final candidate:SourceCandidate;
	final candidates:Map<String, SourceCandidate>;

	public var unresolvedClassValue(default, null):Bool = false;

	public function new(candidate:SourceCandidate, candidates:Map<String, SourceCandidate>) {
		this.candidate = candidate;
		this.candidates = candidates;
	}

	public function run():Void {
		final fn = candidate.functionBody;
		if (fn == null) {
			if (candidate.initializer != null)
				scan([], TyType.unknown(), [], candidate.initializer);
			return;
		}
		final environment = fn.getEnvironment();
		final parameters = environment == null ? [] : [
			for (parameter in environment.getParams())
				new TyLocalBinding(parameter.getIdentity(), parameter.getName(), parameter.getType(), parameter.getKind())
		];
		final result = environment == null ? TyType.unknown() : environment.getReturnType();
		if (fn.getDefaults().length > 0 && needsBoundary(candidate.signature))
			candidate.rejected = true;
		for (value in fn.getDefaults())
			scan([], TyType.unknown(), [], value.getExpression());
		scan(parameters, result, fn.getBody().getStatements(), null);
	}

	function connect(id:String):Void {
		if (!candidate.dependencies.contains(id))
			candidate.dependencies.push(id);
	}

	function scan(parameters:Array<TyLocalBinding>, result:TyType, statements:Array<TypedStmt>, expression:Null<TypedExpr>):Void {
		final locals:Map<String, Bool> = [];
		for (parameter in parameters)
			if (isFunction(parameter.getType())) {
				candidate.usesViews = true;
				if (valueShape(parameter.getType()) == null)
					candidate.rejected = true;
				locals.set(parameter.getIdentity().getCanonicalKey(), true);
			}
		if (isFunction(result))
			candidate.usesViews = true;
		var visit:TypedExpr->Void = null;
		var value:(TypedExpr, Null<OcamlGenericValueShape>) -> Void = null;
		function nested(current:TypedExpr):Void {
			final type = TyAliasExpansion.reveal(current.getType());
			final children = current.getExpressions();
			final result = type.getFunctionReturn();
			final sourceFunction = current.getSourceFunction();
			// A named function reads its own binding. That recursive callback storage needs a separate plan.
			if (sourceFunction != null && sourceFunction.getDeclaredName() != null)
				candidate.rejected = true;
			if (!type.isFunction() || result == null || children.length == 0 || valueShape(type) == null) {
				candidate.rejected = true;
				for (child in children)
					visit(child);
				return;
			}
			if (children.length > 1)
				candidate.rejected = true;
			scan(current.getLocalBindings(), result, [], children[0]);
		}
		function receiver(callee:TypedExpr):Void {
			// A direct static receiver names a declaration; reading a class value elsewhere exposes reflection.
			if (callee.getTag() == FieldRead) {
				for (child in callee.getExpressions())
					if (child.getTag() != RuntimeTypeValue)
						visit(child);
			} else if (callee.getTag() != NameRead)
				visit(callee);
		}
		function call(current:TypedExpr):Void {
			final children = current.getExpressions();
			if (children.length == 0) {
				candidate.rejected = true;
				return;
			}
			final callee = unwrap(children[0]);
			final signature = TyAliasExpansion.reveal(callee.getType());
			final arguments = children.slice(1);
			if (!signature.isFunction()) {
				receiver(callee);
				for (argument in arguments)
					visit(argument);
				return;
			}
			final parameters = signature.getFunctionParameters();
			final returned = signature.getFunctionReturn();
			final boundary = (returned != null && isFunction(returned))
				|| Lambda.exists(parameters, parameter -> isFunction(parameter.type));
			final declaration = callee.getDeclaration();
			if (declaration != null && declaration.getIsStatic()) {
				if (boundary)
					connect(declaration.getIdentity().getCanonicalKey());
			} else if (callee.getTag() == LocalRead || callee.getTag() == Lambda || callee.getTag() == SourceFunction || callee.getTag() == Call) {
				value(callee, valueShape(signature));
			} else {
				if (boundary)
					candidate.rejected = true;
				receiver(callee);
			}
			if (boundary && (arguments.length != parameters.length || valueShape(signature) == null))
				candidate.rejected = true;
			for (index in 0...arguments.length) {
				final argument = arguments[index];
				final expected = index < parameters.length ? parameters[index].type : null;
				if (isFunction(argument.getType()) || (expected != null && isFunction(expected)))
					value(argument, expected == null ? null : valueShape(expected));
				else
					visit(argument);
			}
		}
		value = (source, expected) -> {
			candidate.usesViews = true;
			final actual = valueShape(source.getType());
			if (actual == null || expected == null || crossing(actual, expected) == null)
				candidate.rejected = true;
			final current = unwrap(source);
			switch current.getTag() {
				case LocalRead:
					final bindings = current.getLocalBindings();
					if (bindings.length != 1 || !locals.exists(bindings[0].getIdentity().getCanonicalKey())) candidate.rejected = true;
				case Lambda | SourceFunction: nested(current);
				case Call: call(current);
				case NameRead | FieldRead:
					final declaration = current.getDeclaration();
					final target = declaration == null ? null : candidates.get(declaration.getIdentity().getCanonicalKey());
					if (declaration == null || !declaration.getIsStatic() || target == null || !target.eligible) {
						candidate.rejected = true;
						for (child in current.getExpressions())
							visit(child);
					} else if (needsBoundary(actual)) connect(declaration.getIdentity().getCanonicalKey());
				case _:
					candidate.rejected = true;
					for (child in current.getExpressions())
						visit(child);
			}
		};
		function local(bindings:Array<TyLocalBinding>, expressions:Array<TypedExpr>):Void {
			if (bindings.length == 1 && isFunction(bindings[0].getType())) {
				final shape = valueShape(bindings[0].getType());
				if (expressions.length != 1 || shape == null) {
					candidate.rejected = true;
					for (child in expressions)
						visit(child);
				} else {
					value(expressions[0], shape);
					locals.set(bindings[0].getIdentity().getCanonicalKey(), true);
				}
			} else
				for (child in expressions)
					visit(child);
		}
		visit = source -> {
			final current = unwrap(source);
			final children = current.getExpressions();
			if (isFunction(current.getType()))
				candidate.rejected = true;
			final nominal = current.getType().getNominalIdentity();
			if (current.getTag() != RuntimeTypeValue
				&& (current.getType().getClassValueScheme() != null || (nominal != null && nominal.getCanonicalName() == "Class"))) {
				candidate.rejected = true;
				unresolvedClassValue = true;
			}
			switch current.getTag() {
				case VariableDeclaration: local(current.getLocalBindings(), children);
				case ReturnExpr if (children.length == 1 && isFunction(result)): value(children[0], valueShape(result));
				case Call: call(current);
				case Binary
					if (children.length == 2
						&& ["==", "!="].contains(current.getTexts()[0])
						&& (isFunction(children[0].getType()) || isFunction(children[1].getType()))):
					for (child in children)
						value(child, valueShape(child.getType()));
				case Lambda | SourceFunction: nested(current);
				case NameRead | FieldRead if (needsBoundary(valueShape(current.getType()))):
					final declaration = current.getDeclaration();
					if (declaration != null)
						connect(declaration.getIdentity().getCanonicalKey());
					for (child in children)
						visit(child);
				case RuntimeTypeValue:
					candidate.rejected = true;
					final target = current.getRuntimeTypeTarget();
					final identity = target == null ? null : target.getDeclarationIdentity();
					if (identity == null) unresolvedClassValue = true; else for (other in candidates)
						if (other.owner == identity.getCanonicalName() && needsBoundary(other.signature))
							connect(other.id);
				case _:
					for (child in children)
						visit(child);
			}
		};
		function statement(current:TypedStmt):Void {
			final expressions = current.getExpressions();
			switch current.getTag() {
				case Var:
					local(current.getLocalBindings(), expressions);
				case Return if (expressions.length == 1 && isFunction(result)):
					value(expressions[0], valueShape(result));
				case _:
					for (child in expressions)
						visit(child);
			}
			for (child in current.getStatements())
				statement(child);
		}
		for (current in statements)
			statement(current);
		if (expression != null) {
			if (isFunction(result) && isFunction(expression.getType()))
				value(expression, valueShape(result));
			else
				visit(expression);
		}
	}
}

/** Grouping and written type checks preserve the producer. Unchecked casts need a separate callback conversion plan. */
private function unwrap(expression:TypedExpr):TypedExpr {
	return switch expression.getTag() {
		case Parenthesized | CheckType: unwrap(expression.getExpressions()[0]);
		case _: expression;
	};
}
