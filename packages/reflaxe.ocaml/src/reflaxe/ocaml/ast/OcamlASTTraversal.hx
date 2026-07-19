package reflaxe.ocaml.ast;

import reflaxe.ocaml.ast.OcamlExpr;
import reflaxe.ocaml.ast.OcamlExpr.OcamlBinop;
import reflaxe.ocaml.ast.OcamlPat;
import reflaxe.ocaml.ast.OcamlTypeExpr;

/**
	Defines the authoritative structural child contract for the OCaml target AST.

	Immediate mapping is exhaustive and preserves the original node when every
	child mapper returns the original child. Generic walks and folds are derived
	from that same mapping contract, so adding an AST constructor cannot silently
	turn it into a leaf in one of those consumers.

	`ERaw` is deliberately opaque: its text is not parsed or traversed. `EPos` is
	structurally transparent and always exposes its wrapped expression. Lexical
	scope is outside this module; analyses that care about binding or shadowing
	must add an explicit scope-aware layer instead of treating this walk as one.
**/
class OcamlASTTraversal {
	/** Rebuilds exactly the immediate children of one expression node. */
	public static function mapExprImmediate(expression:OcamlExpr, mapExpression:OcamlExpr->OcamlExpr, mapPattern:OcamlPat->OcamlPat,
			mapType:OcamlTypeExpr->OcamlTypeExpr):OcamlExpr {
		return switch (expression) {
			case EConst(_), EIdent(_), ERaw(_):
				expression;
			case EPos(pos, inner):
				final mappedInner = mapExpression(inner);
				mappedInner == inner ? expression : EPos(pos, mappedInner);
			case ERaise(exn):
				final mappedExn = mapExpression(exn);
				mappedExn == exn ? expression : ERaise(mappedExn);
			case ELet(name, value, body, isRec):
				mapLet(expression, name, value, body, isRec, mapExpression);
			case EFun(params, body):
				mapFunction(expression, params, body, mapExpression, mapPattern);
			case EApp(fn, args):
				mapApplication(expression, fn, args, mapExpression);
			case EAppArgs(fn, args):
				mapLabelledApplication(expression, fn, args, mapExpression);
			case EBinop(op, left, right):
				mapBinaryOperation(expression, op, left, right, mapExpression);
			case EUnop(op, inner):
				final mappedInner = mapExpression(inner);
				mappedInner == inner ? expression : EUnop(op, mappedInner);
			case EIf(condition, thenExpression, elseExpression):
				mapIf(expression, condition, thenExpression, elseExpression, mapExpression);
			case EMatch(scrutinee, cases):
				mapMatch(expression, scrutinee, cases, mapExpression, mapPattern);
			case ETry(body, cases):
				mapTry(expression, body, cases, mapExpression, mapPattern);
			case ESeq(expressions):
				final mappedExpressions = mapArrayPreservingIdentity(expressions, mapExpression);
				mappedExpressions == expressions ? expression : ESeq(mappedExpressions);
			case EWhile(condition, body):
				mapWhile(expression, condition, body, mapExpression);
			case EList(items):
				final mappedItems = mapArrayPreservingIdentity(items, mapExpression);
				mappedItems == items ? expression : EList(mappedItems);
			case ERecord(fields):
				final mappedFields = mapArrayPreservingIdentity(fields, field -> {
					final mappedValue = mapExpression(field.value);
					mappedValue == field.value ? field : {name: field.name, value: mappedValue};
				});
				mappedFields == fields ? expression : ERecord(mappedFields);
			case EField(target, field):
				final mappedTarget = mapExpression(target);
				mappedTarget == target ? expression : EField(mappedTarget, field);
			case EAssign(op, left, right):
				mapAssignment(expression, op, left, right, mapExpression);
			case ETuple(items):
				final mappedItems = mapArrayPreservingIdentity(items, mapExpression);
				mappedItems == items ? expression : ETuple(mappedItems);
			case EAnnot(inner, type):
				mapExpressionAnnotation(expression, inner, type, mapExpression, mapType);
		}
	}

	/** Rebuilds exactly the immediate children of one pattern node. */
	public static function mapPatternImmediate(pattern:OcamlPat, mapPattern:OcamlPat->OcamlPat, mapType:OcamlTypeExpr->OcamlTypeExpr):OcamlPat {
		return switch (pattern) {
			case PAny, PVar(_), PConst(_):
				pattern;
			case PTuple(items):
				final mappedItems = mapArrayPreservingIdentity(items, mapPattern);
				mappedItems == items ? pattern : PTuple(mappedItems);
			case POr(items):
				final mappedItems = mapArrayPreservingIdentity(items, mapPattern);
				mappedItems == items ? pattern : POr(mappedItems);
			case PConstructor(name, args):
				final mappedArgs = mapArrayPreservingIdentity(args, mapPattern);
				mappedArgs == args ? pattern : PConstructor(name, mappedArgs);
			case PRecord(fields):
				final mappedFields = mapArrayPreservingIdentity(fields, field -> {
					final mappedPattern = mapPattern(field.pat);
					mappedPattern == field.pat ? field : {name: field.name, pat: mappedPattern};
				});
				mappedFields == fields ? pattern : PRecord(mappedFields);
			case PAnnot(inner, type):
				mapPatternAnnotation(pattern, inner, type, mapPattern, mapType);
		}
	}

	/** Rebuilds exactly the immediate children of one OCaml type-expression node. */
	public static function mapTypeImmediate(type:OcamlTypeExpr, mapType:OcamlTypeExpr->OcamlTypeExpr):OcamlTypeExpr {
		return switch (type) {
			case TIdent(_), TVar(_):
				type;
			case TApp(name, params):
				final mappedParams = mapArrayPreservingIdentity(params, mapType);
				mappedParams == params ? type : TApp(name, mappedParams);
			case TArrow(from, to):
				mapArrowType(type, from, to, mapType);
			case TTuple(items):
				final mappedItems = mapArrayPreservingIdentity(items, mapType);
				mappedItems == items ? type : TTuple(mappedItems);
			case TRecord(fields):
				final mappedFields = mapArrayPreservingIdentity(fields, field -> {
					final mappedType = mapType(field.typ);
					mappedType == field.typ ? field : {name: field.name, isMutable: field.isMutable, typ: mappedType};
				});
				mappedFields == fields ? type : TRecord(mappedFields);
		}
	}

	/** Applies post-order transformations to a complete expression subtree. */
	public static function mapExprTree(expression:OcamlExpr, mapExpression:OcamlExpr->OcamlExpr, mapPattern:OcamlPat->OcamlPat,
			mapType:OcamlTypeExpr->OcamlTypeExpr):OcamlExpr {
		function visitType(type:OcamlTypeExpr):OcamlTypeExpr {
			return mapType(mapTypeImmediate(type, visitType));
		}
		function visitPattern(pattern:OcamlPat):OcamlPat {
			return mapPattern(mapPatternImmediate(pattern, visitPattern, visitType));
		}
		function visitExpression(current:OcamlExpr):OcamlExpr {
			return mapExpression(mapExprImmediate(current, visitExpression, visitPattern, visitType));
		}
		return visitExpression(expression);
	}

	/** Walks expressions, patterns, and types in deterministic pre-order. */
	public static function walkExprPre(expression:OcamlExpr, visitExpression:OcamlExpr->Void, visitPattern:OcamlPat->Void, visitType:OcamlTypeExpr->Void):Void {
		visitExpression(expression);
		mapExprImmediate(expression, child -> {
			walkExprPre(child, visitExpression, visitPattern, visitType);
			return child;
		}, child -> {
			walkPatternPre(child, visitPattern, visitType);
			return child;
		}, child -> {
			walkTypePre(child, visitType);
			return child;
		});
	}

	/** Walks a pattern subtree and any type annotations in deterministic pre-order. */
	public static function walkPatternPre(pattern:OcamlPat, visitPattern:OcamlPat->Void, visitType:OcamlTypeExpr->Void):Void {
		visitPattern(pattern);
		mapPatternImmediate(pattern, child -> {
			walkPatternPre(child, visitPattern, visitType);
			return child;
		}, child -> {
			walkTypePre(child, visitType);
			return child;
		});
	}

	/** Walks a type-expression subtree in deterministic pre-order. */
	public static function walkTypePre(type:OcamlTypeExpr, visitType:OcamlTypeExpr->Void):Void {
		visitType(type);
		mapTypeImmediate(type, child -> {
			walkTypePre(child, visitType);
			return child;
		});
	}

	/** Folds the same deterministic event stream produced by `walkExprPre`. */
	public static function foldExpr<T>(expression:OcamlExpr, initial:T, foldExpression:(T, OcamlExpr) -> T, foldPattern:(T, OcamlPat) -> T,
			foldType:(T, OcamlTypeExpr) -> T):T {
		var result = initial;
		walkExprPre(expression, current -> result = foldExpression(result, current), current -> result = foldPattern(result, current),
			current -> result = foldType(result, current));
		return result;
	}

	static inline function mapLet(original:OcamlExpr, name:String, value:OcamlExpr, body:OcamlExpr, isRec:Bool, mapExpression:OcamlExpr->OcamlExpr):OcamlExpr {
		final mappedValue = mapExpression(value);
		final mappedBody = mapExpression(body);
		if (mappedValue == value && mappedBody == body)
			return original;
		return ELet(name, mappedValue, mappedBody, isRec);
	}

	static inline function mapFunction(original:OcamlExpr, params:Array<OcamlPat>, body:OcamlExpr, mapExpression:OcamlExpr->OcamlExpr,
			mapPattern:OcamlPat->OcamlPat):OcamlExpr {
		final mappedParams = mapArrayPreservingIdentity(params, mapPattern);
		final mappedBody = mapExpression(body);
		if (mappedParams == params && mappedBody == body)
			return original;
		return EFun(mappedParams, mappedBody);
	}

	static inline function mapApplication(original:OcamlExpr, fn:OcamlExpr, args:Array<OcamlExpr>, mapExpression:OcamlExpr->OcamlExpr):OcamlExpr {
		final mappedFn = mapExpression(fn);
		final mappedArgs = mapArrayPreservingIdentity(args, mapExpression);
		if (mappedFn == fn && mappedArgs == args)
			return original;
		return EApp(mappedFn, mappedArgs);
	}

	static inline function mapLabelledApplication(original:OcamlExpr, fn:OcamlExpr, args:Array<OcamlApplyArg>, mapExpression:OcamlExpr->OcamlExpr):OcamlExpr {
		final mappedFn = mapExpression(fn);
		final mappedArgs = mapArrayPreservingIdentity(args, argument -> {
			final mappedArgument = mapExpression(argument.expr);
			return mappedArgument == argument.expr ? argument : {
				label: argument.label,
				isOptional: argument.isOptional,
				expr: mappedArgument
			};
		});
		if (mappedFn == fn && mappedArgs == args)
			return original;
		return EAppArgs(mappedFn, mappedArgs);
	}

	static inline function mapBinaryOperation(original:OcamlExpr, op:OcamlBinop, left:OcamlExpr, right:OcamlExpr,
			mapExpression:OcamlExpr->OcamlExpr):OcamlExpr {
		final mappedLeft = mapExpression(left);
		final mappedRight = mapExpression(right);
		if (mappedLeft == left && mappedRight == right)
			return original;
		return EBinop(op, mappedLeft, mappedRight);
	}

	static inline function mapIf(original:OcamlExpr, condition:OcamlExpr, thenExpression:OcamlExpr, elseExpression:OcamlExpr,
			mapExpression:OcamlExpr->OcamlExpr):OcamlExpr {
		final mappedCondition = mapExpression(condition);
		final mappedThen = mapExpression(thenExpression);
		final mappedElse = mapExpression(elseExpression);
		if (mappedCondition == condition && mappedThen == thenExpression && mappedElse == elseExpression)
			return original;
		return EIf(mappedCondition, mappedThen, mappedElse);
	}

	static inline function mapMatch(original:OcamlExpr, scrutinee:OcamlExpr, cases:Array<OcamlMatchCase>, mapExpression:OcamlExpr->OcamlExpr,
			mapPattern:OcamlPat->OcamlPat):OcamlExpr {
		final mappedScrutinee = mapExpression(scrutinee);
		final mappedCases = mapMatchCases(cases, mapExpression, mapPattern);
		if (mappedScrutinee == scrutinee && mappedCases == cases)
			return original;
		return EMatch(mappedScrutinee, mappedCases);
	}

	static inline function mapTry(original:OcamlExpr, body:OcamlExpr, cases:Array<OcamlMatchCase>, mapExpression:OcamlExpr->OcamlExpr,
			mapPattern:OcamlPat->OcamlPat):OcamlExpr {
		final mappedBody = mapExpression(body);
		final mappedCases = mapMatchCases(cases, mapExpression, mapPattern);
		if (mappedBody == body && mappedCases == cases)
			return original;
		return ETry(mappedBody, mappedCases);
	}

	static inline function mapWhile(original:OcamlExpr, condition:OcamlExpr, body:OcamlExpr, mapExpression:OcamlExpr->OcamlExpr):OcamlExpr {
		final mappedCondition = mapExpression(condition);
		final mappedBody = mapExpression(body);
		if (mappedCondition == condition && mappedBody == body)
			return original;
		return EWhile(mappedCondition, mappedBody);
	}

	static inline function mapAssignment(original:OcamlExpr, op:OcamlAssignOp, left:OcamlExpr, right:OcamlExpr, mapExpression:OcamlExpr->OcamlExpr):OcamlExpr {
		final mappedLeft = mapExpression(left);
		final mappedRight = mapExpression(right);
		if (mappedLeft == left && mappedRight == right)
			return original;
		return EAssign(op, mappedLeft, mappedRight);
	}

	static inline function mapExpressionAnnotation(original:OcamlExpr, inner:OcamlExpr, type:OcamlTypeExpr, mapExpression:OcamlExpr->OcamlExpr,
			mapType:OcamlTypeExpr->OcamlTypeExpr):OcamlExpr {
		final mappedInner = mapExpression(inner);
		final mappedType = mapType(type);
		if (mappedInner == inner && mappedType == type)
			return original;
		return EAnnot(mappedInner, mappedType);
	}

	static inline function mapPatternAnnotation(original:OcamlPat, inner:OcamlPat, type:OcamlTypeExpr, mapPattern:OcamlPat->OcamlPat,
			mapType:OcamlTypeExpr->OcamlTypeExpr):OcamlPat {
		final mappedInner = mapPattern(inner);
		final mappedType = mapType(type);
		if (mappedInner == inner && mappedType == type)
			return original;
		return PAnnot(mappedInner, mappedType);
	}

	static inline function mapArrowType(original:OcamlTypeExpr, from:OcamlTypeExpr, to:OcamlTypeExpr, mapType:OcamlTypeExpr->OcamlTypeExpr):OcamlTypeExpr {
		final mappedFrom = mapType(from);
		final mappedTo = mapType(to);
		if (mappedFrom == from && mappedTo == to)
			return original;
		return TArrow(mappedFrom, mappedTo);
	}

	static function mapMatchCases(cases:Array<OcamlMatchCase>, mapExpression:OcamlExpr->OcamlExpr, mapPattern:OcamlPat->OcamlPat):Array<OcamlMatchCase> {
		return mapArrayPreservingIdentity(cases, matchCase -> {
			final mappedPattern = mapPattern(matchCase.pat);
			final mappedGuard = matchCase.guard == null ? null : mapExpression(matchCase.guard);
			final mappedExpression = mapExpression(matchCase.expr);
			return mappedPattern == matchCase.pat && mappedGuard == matchCase.guard && mappedExpression == matchCase.expr ? matchCase : {
				pat: mappedPattern,
				guard: mappedGuard,
				expr: mappedExpression
			};
		});
	}

	static function mapArrayPreservingIdentity<T>(items:Array<T>, mapItem:T->T):Array<T> {
		var mappedItems:Null<Array<T>> = null;
		for (index in 0...items.length) {
			final original = items[index];
			final mapped = mapItem(original);
			if (mappedItems == null && mapped != original)
				mappedItems = items.copy();
			if (mappedItems != null)
				mappedItems[index] = mapped;
		}
		return mappedItems == null ? items : mappedItems;
	}
}
