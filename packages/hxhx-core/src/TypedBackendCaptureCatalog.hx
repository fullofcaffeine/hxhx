import haxe.ds.StringMap;

/** One projected closure object and the immutable typed facts that authorize its captures. */
private typedef ProjectedCaptureOccurrence = {
	final expression:HxExpr;
	final facts:TypedCaptureFunction;
}

/** Each traversal owns its occurrence list and duplicate checks. */
private typedef CaptureProjectionVisit = {
	final entries:Array<ProjectedCaptureOccurrence>;
	final seen:StringMap<Bool>;
}

/** Preorder position binds a compiler-added annotation to the checked published body. */
private typedef ProjectedCallableAscription = {
	final index:Int;
	final expression:HxExpr;
	final value:HxExpr;
}

/**
	Binds capture decisions to one exact projected function body.

	The typed source and lowered body own semantic revisions. A reconstructed body
	check proves that this projection carries those facts. The source-shaped body
	remains mutable, so every public lookup also checks its complete current shape.
	Matching a function target string alone never authorizes an emitted closure.
 */
class TypedBackendCaptureCatalog {
	final owner:TypedCaptureProjectionOwner;
	final plan:TypedCapturePlan;
	final bodyIdentity:String;
	final entries:Array<ProjectedCaptureOccurrence>;
	final byTarget:StringMap<TypedCaptureFunction> = new StringMap();
	final callableTypes:StringMap<TyType> = new StringMap();
	final ascriptions:Array<ProjectedCallableAscription> = [];

	public function new(owner:TypedCaptureProjectionOwner, locals:TypedBackendLocalCatalog) {
		this.owner = owner;
		plan = switch owner {
			case FunctionBody(source, lowered, _): TypedCapturePlan.afterLowering(source, lowered);
			case FieldInitializer(source, lowered, _): TypedCapturePlan.afterInitializerLowering(source, initializerEntries(lowered));
		};
		bodyIdentity = projectedFingerprint();
		final projectionFacts = new TypedBodyProjectionBuilder(plan.ownerIdentity, plan.sourceBodyRevision);
		final expectedExpressions = new Array<HxExpr>();
		final expectedFingerprint = switch owner {
			case FunctionBody(_, lowered, _):
				final expected = TypedBodySource.functionDeclaration(lowered, locals, projectionFacts);
				TypedBackendSourceWalk.functionDeclaration(expected, value -> expectedExpressions.push(value), _ -> {});
				functionIdentity(expected);
			case FieldInitializer(source, lowered, _):
				final expressions = [
					for (entry in initializerEntries(lowered))
						TypedBodySource.expression(entry, locals, projectionFacts)
				];
				final position = source.getExpression().getPosition();
				final expected:HxExpr = lowered.steps.length == 0
					&& lowered.value != null ? expressions[0] : ELoweredControl(Initializer(lowered.value != null), plan.ownerIdentity, expressions,
						position == null ? HxPos.unknown() : position);
				TypedBackendSourceWalk.expression(expected, value -> expectedExpressions.push(value));
				TypedBodyFingerprint.exactExpression(expected);
		};
		if (bodyIdentity != expectedFingerprint)
			throw "capture catalog requires the exact lowered function projection";
		final publishedExpressions = expressionOrder();
		for (annotation in projectionFacts.getCallableAscriptions()) {
			final index = expectedExpressions.indexOf(annotation);
			if (index < 0)
				continue;
			final published = publishedExpressions[index];
			switch published {
				case ECast(value, _):
					ascriptions.push({index: index, expression: published, value: value});
				case _:
					throw "callable annotation differs from the checked projection";
			}
		}
		for (fact in plan.getBindings())
			locals.projectedName(fact.binding);
		final functions = plan.getFunctions();
		for (fn in functions)
			if (fn.controlTargetIdentity != null)
				byTarget.set(fn.controlTargetIdentity, fn);
		for (expression in plan.getFunctionExpressions())
			callableTypes.set(plan.requireFunction(expression).identity, expression.getType());
		entries = collect();
		if (entries.length != functions.length - 1)
			throw "capture catalog does not account for every lowered closure";
	}

	/** Both bodies have equal exact structure before their expression positions are paired. */
	function expressionOrder():Array<HxExpr> {
		final expressions = new Array<HxExpr>();
		switch owner {
			case FunctionBody(_, _, declaration):
				TypedBackendSourceWalk.functionDeclaration(declaration, value -> expressions.push(value), _ -> {});
			case FieldInitializer(_, _, declaration):
				TypedBackendSourceWalk.expression(HxFieldDecl.getInit(declaration), value -> expressions.push(value));
		}
		return expressions;
	}

	static function initializerEntries(lowered:TypedControlLowering.LoweredFieldInitializer):Array<TypedExpr>
		return lowered.value == null ? lowered.steps.copy() : lowered.steps.concat([lowered.value]);

	function projectedFingerprint():String {
		return switch owner {
			case FunctionBody(_, _, declaration): functionIdentity(declaration);
			case FieldInitializer(_, _, declaration): TypedBodyFingerprint.exactExpression(HxFieldDecl.getInit(declaration));
		};
	}

	/** Conditional defaults and the ordinary body are one immutable executable projection. */
	static function functionIdentity(declaration:HxFunctionDecl):String {
		return CompilerCacheIdentity.encode([
			TypedFunctionDefault.sourceIdentity(HxFunctionDecl.getArgs(declaration)),
			TypedBodyFingerprint.exactStatements(HxFunctionDecl.getBody(declaration))
		]);
	}

	function collect():Array<ProjectedCaptureOccurrence> {
		final visit:CaptureProjectionVisit = {entries: [], seen: new StringMap()};
		final root = plan.getFunctions()[0].identity;
		switch owner {
			case FunctionBody(_, _, declaration):
				for (argument in HxFunctionDecl.getArgs(declaration))
					switch HxFunctionArg.getDefaultValue(argument) {
						case NoDefault:
						case Default(expression): scanExpression(expression, root, visit);
					}
				for (statement in HxFunctionDecl.getBody(declaration))
					scanStatement(statement, root, visit);
			case FieldInitializer(_, _, declaration):
				scanExpression(HxFieldDecl.getInit(declaration), root, visit);
		}
		return visit.entries;
	}

	function scanStatement(node:HxStmt, parent:String, visit:CaptureProjectionVisit):Void {
		TypedBackendSourceWalk.statementChildren(node, value -> scanExpression(value, parent, visit), child -> scanStatement(child, parent, visit));
	}

	/** Quotations retain source syntax; only executable lambdas can acquire capture facts. */
	function scanExpression(node:HxExpr, parent:String, visit:CaptureProjectionVisit):Void {
		switch node {
			case EMacroExpr(_, _) | EMacroType(_):
				return;
			case ELambda(_, body):
				final target = switch body {
					case ELoweredControl(FunctionBody, identity, _, _): identity;
					case _: throw "projected closure lacks its lowered function origin";
				};
				final facts = byTarget.get(target);
				if (facts == null || facts.parentIdentity != parent)
					throw "projected closure belongs to another lexical function";
				if (visit.seen.exists(target))
					throw "projected function repeats one closure origin";
				visit.seen.set(target, true);
				visit.entries.push({expression: node, facts: facts});
				scanExpression(body, facts.identity, visit);
				return;
			case ESourceFunction(_, _, _, _):
				throw "executable projection retains an unlowered source function";
			case _:
		}
		TypedBackendSourceWalk.expressionChildren(node, child -> scanExpression(child, parent, visit));
	}

	public function assertOwner(owner:String, sourceRevision:String):Void {
		if (plan.ownerIdentity != owner || plan.sourceBodyRevision != sourceRevision)
			throw "capture catalog belongs to another function or source revision";
	}

	/** Mutation of either semantic input or the published body invalidates this catalog. */
	public function assertCurrent():Void {
		switch owner {
			case FunctionBody(source, lowered, _):
				source.assertParsedBodyCurrent();
				if (CompilerTypedTreeRevision.functionBody(source) != plan.sourceBodyRevision)
					throw "capture catalog has stale authored input";
				plan.assertCurrent(lowered);
			case FieldInitializer(source, lowered, _):
				if (CompilerTypedTreeRevision.expression(source.getField().getCanonicalKey(), source.getExpression()) != plan.sourceBodyRevision)
					throw "capture catalog has stale authored input";
				plan.assertInitializerCurrent(source, initializerEntries(lowered));
		}
		if (projectedFingerprint() != bodyIdentity)
			throw "capture catalog projection was mutated";
		final current = collect();
		if (current.length != entries.length)
			throw "capture catalog closure occurrences changed";
		for (index in 0...entries.length)
			if (current[index].expression != entries[index].expression)
				throw "capture catalog closure occurrences changed";
		final expressions = expressionOrder();
		for (annotation in ascriptions)
			if (expressions[annotation.index] != annotation.expression)
				throw "capture catalog callable annotation occurrences changed";
	}

	public function getPlan():TypedCapturePlan {
		assertCurrent();
		return plan;
	}

	public function getExpressions():Array<HxExpr> {
		assertCurrent();
		return [for (entry in entries) entry.expression];
	}

	public function require(expression:HxExpr):TypedCaptureFunction {
		assertCurrent();
		for (entry in entries)
			if (entry.expression == expression)
				return entry.facts;
		throw "closure is not an exact occurrence in this function projection";
	}

	/** The lowered typed expression owns its signature; annotations and rendered text do not. */
	public function requireCallableType(expression:HxExpr):TyType {
		final facts = require(expression);
		final type = callableTypes.get(facts.identity);
		if (type == null || !type.isFunction())
			throw "cataloged closure lacks a typed callable signature";
		return type;
	}

	/** Strip only this projection's compiler-added annotation, never an authored cast. */
	public function requireAscribedClosure(expression:HxExpr):HxExpr {
		assertCurrent();
		for (annotation in ascriptions)
			if (annotation.expression == expression) {
				require(annotation.value);
				return annotation.value;
			}
		throw "expression is not an exact compiler-added callable annotation";
	}
}
