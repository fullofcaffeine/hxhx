package backend.cpp;

import backend.cpp.CppManagedCallContext.CppManagedEnclosingApplication;
import backend.cpp.CppManagedConstructor.CppManagedConstructorTarget;
import backend.cpp.CppManagedInstanceMethod.CppManagedInstanceMethodTarget;

/** The target's emitted entry and environment must belong to this exact closure occurrence. */
typedef CppManagedClosureLink = {
	final expression:HxExpr;
	final environmentName:String;
	final entrySymbol:String;
}

/** A field initializer has its own facts and must never be represented as a fabricated method. */
enum CppManagedExpressionOwner {
	CallableBody(access:CppManagedLocalAccess);
	FieldInitializer(projection:TypedBackendFieldInitializerProjection);
}

/** Native symbols and closure links come from the enclosing target emission scope. */
typedef CppManagedRootedExpressionInput = {
	final owner:CppManagedExpressionOwner;

	/** Calls retain the exact function or field application of their lexical owner. */
	final ?callContext:CppManagedEnclosingApplication;

	/** Direct field expressions use their declaring class application, not a method application. */
	final ?initializerApplication:CppManagedInitializerApplication;

	final heap:String;
	final temporaryPrefix:String;
	final resolve:HxExpr->CppManagedClosureLink;
	final ?resolveStatic:String->CppManagedStaticTarget;
	final ?statics:CppManagedStaticStorage;
	final ?casts:CppManagedCastPlan;
	final ?classes:CppManagedClassStorage;
	final ?enums:CppManagedEnumDescriptors;
	final ?defaultValue:TyType->String;
	final ?resolveConstructor:String->CppManagedConstructorTarget;
	final ?resolveInstance:(TypedBackendInstanceCallOccurrence, Null<CppManagedEnclosingApplication>) -> CppManagedInstanceMethodTarget;

	/** Active compile-time inline expansion path; repeated declarations indicate a cycle. */
	final ?inlineFields:Array<String>;
}

/** Static selection is already typed; only local callable values need runtime callee evaluation. */
private typedef ManagedSourceInvocation = {
	final callee:HxExpr;
	final arguments:Array<HxExpr>;
	final staticTarget:Null<CppManagedStaticTarget>;
}

/**
	Emit common values into an existing root without returning an unrooted allocation.
	A child function literal snapshots existing cell edges, constructs its traced
	environment and callable, then publishes the callable before temporary roots
	leave. Exact lexical parent and entry-link identities prevent another closure's
	code or capture layout from being selected by equal source text.
	Other expression families need explicit sequencing support at this boundary.
 */
class CppManagedRootedExpression {
	final input:CppManagedRootedExpressionInput;
	var access(get, never):CppManagedLocalAccess;
	final locals:CppManagedExpressionLocals;

	/** Local bindings and closures require the capture plan of an actual callable body. */
	function get_access():CppManagedLocalAccess {
		return switch input.owner {
			case CallableBody(selected): selected;
			case FieldInitializer(_): throw "managed initializer requires its own local or closure storage plan";
		};
	}

	function requireExpression(expression:HxExpr):Void {
		switch input.owner {
			case CallableBody(selected):
				selected.requireExpression(expression);
			case FieldInitializer(projection):
				projection.requireExpression(expression);
		}
	}

	/** Class operations still belong to the exact program's executable owner, even with parameter-only operands. */
	function requireClassOperation(expression:HxExpr):Void {
		requireExpression(expression);
		switch input.owner {
			case CallableBody(selected):
				selected.assertClassStorage(input.classes);
			case FieldInitializer(projection):
				input.classes.assertInitializer(projection);
		}
	}

	function aggregate(expression:HxExpr):TypedBackendAggregateOccurrence {
		return switch input.owner {
			case CallableBody(selected): selected.aggregate(expression);
			case FieldInitializer(projection): projection.requireAggregate(expression);
		};
	}

	/** Marker spelling only selects the lookup; the exact executable catalog supplies the fact. */
	function runtimeType(expression:HxExpr):Null<TypedBackendRuntimeTypeOccurrence> {
		if (!TypedRuntimeTypeSource.isMarker(expression))
			return null;
		return switch input.owner {
			case CallableBody(selected): selected.runtimeType(expression);
			case FieldInitializer(projection): projection.requireRuntimeType(expression);
		};
	}

	/** Source marker names alone never select native instance operations. */
	function instanceCall(expression:HxExpr):Null<TypedBackendInstanceCallOccurrence> {
		return switch input.owner {
			case CallableBody(selected): selected.instanceCall(expression);
			case FieldInitializer(projection): projection.findInstanceCall(expression);
		};
	}

	/** Implicit conversions retain typing's guarantee; authored casts need the exact target plan. */
	function converted(expression:HxExpr):Null<TypedBackendCastOccurrence> {
		final occurrence = switch input.owner {
			case CallableBody(selected): selected.findCast(expression);
			case FieldInitializer(projection): projection.findCast(expression);
		};
		if (occurrence == null)
			return null;
		if (!occurrence.isRepresentationPreserving()) {
			if (input.casts == null)
				throw "managed cast requires an explicit runtime conversion plan";
			input.casts.requireStoredValue(occurrence);
		}
		CppManagedClosureAbi.assertComplete(occurrence.getSourceType());
		CppManagedClosureAbi.assertComplete(occurrence.getTargetType());
		if (valueType(occurrence.getOperand()).getSemanticKey() != occurrence.getSourceType().getSemanticKey())
			throw "managed cast operand differs from its retained source type";
		return occurrence;
	}

	public function new(input:CppManagedRootedExpressionInput) {
		if (input == null
			|| input.owner == null
			|| input.resolve == null
			|| !identifier(input.heap)
			|| !identifier(input.temporaryPrefix)
			|| !StringTools.startsWith(input.temporaryPrefix, "hxhx_value_"))
			throw "managed value emission requires an owner and allocated native symbols";
		if (input.initializerApplication != null) {
			input.initializerApplication.assertCurrent();
			switch input.owner {
				case FieldInitializer(projection) if (projection == input.initializerApplication.projection):
				case _:
					throw "initializer expression application belongs to another field";
			}
		}
		this.input = input;
		locals = new CppManagedExpressionLocals(input.owner, input.temporaryPrefix, input.initializerApplication);
		switch input.owner {
			case CallableBody(selected):
				selected.plan.requireFunction(selected.owner);
			case FieldInitializer(projection):
				projection.assertCurrent();
		}
	}

	/**
		Complete each Boolean test in its own expression scope before control consumes it.
		The shared renderer reevaluates this expression at each loop test. Only admitted
		value expressions enter here; source returns cannot be moved into this native lambda.
	 */
	public function renderControlValue(value:HxExpr, nativeType:String):String {
		if (nativeType != "bool")
			return access.render(value, nativeType);
		return CppManagedBoolean.renderCondition(value, {
			heap: input.heap,
			prefix: input.temporaryPrefix,
			valueType: valueType,
			requireExpression: requireExpression,
			renderValue: render
		});
	}

	/** Select one arm after rooted scrutinee evaluation; shared lowering owns its result writes. */
	public function renderSwitch(value:HxExpr, patterns:Array<HxSwitchPattern>, indent:String, renderBody:(Int, String) -> Array<String>):Array<String> {
		return CppManagedSwitch.render({
			value: value,
			type: valueType(value),
			patterns: patterns,
			heap: input.heap,
			prefix: input.temporaryPrefix + "switch_",
			renderValue: render,
			renderBody: renderBody
		}, indent);
	}

	/** Retain one iterable and create each binding at its exact loop-iteration event. */
	public function renderFor(binding:HxForBinding, iterable:HxExpr, indent:String, renderBody:String->Array<String>):Array<String> {
		switch iterable {
			case ERange(start, end):
				if (valueType(start).getSemanticKey() != "primitive:Int" || valueType(end).getSemanticKey() != "primitive:Int")
					throw "managed range requires complete integer bounds";
				return CppManagedRangeIteration.render({
					access: access,
					binding: binding,
					iterable: iterable,
					start: start,
					end: end,
					heap: input.heap,
					prefix: input.temporaryPrefix + "range_",
					renderValue: render,
					renderBody: renderBody
				}, indent);
			case _:
		}
		return CppManagedArrayIteration.render({
			access: access,
			binding: binding,
			iterable: iterable,
			type: valueType(iterable),
			heap: input.heap,
			prefix: input.temporaryPrefix + "loop_",
			renderValue: render,
			renderBody: renderBody
		}, indent);
	}

	/** Preserve the declared result's null contract before publishing into the caller's root. */
	public function renderRootedReturn(value:HxExpr, destination:String, indent:String):Array<String> {
		final abi = access.plan.requireFunction(access.owner).abi;
		if (abi.result != RootedResult)
			throw 'managed rooted return requires an explicit typed conversion';
		return renderTransfer(value, abi.signature.getFunctionReturn(), destination, indent);
	}

	/** Context may specialize an exact Array class literal, but cannot narrow a stored erased handle. */
	public function acceptsStoredTransfer(value:HxExpr, target:TyType):Bool {
		if (CppManagedValueTransfer.accepts(target, valueType(value), input.casts))
			return true;
		if (input.classes == null)
			return false;
		var selected = value;
		while (true)
			switch selected {
				case EParenthesized(inner, _) | EUntyped(inner):
					requireExpression(selected);
					selected = inner;
				case _:
					return input.classes.acceptsArrayLiteral(runtimeType(selected), target);
			}
	}

	/** Execute representation-changing recovery explicitly; ordinary transfers remain copies. */
	public function renderTransfer(value:HxExpr, target:TyType, destination:String, indent:String):Array<String> {
		if (acceptsStoredTransfer(value, target))
			return render(value, destination, indent);
		final source = valueType(value);
		if (CppManagedValueTransfer.needsScalarConversion(target, source, input.casts))
			return render(value, destination, indent).concat(CppManagedValueTransfer.convertRoot(target, source, destination, indent, input.casts));
		if (CppManagedArrayRecovery.selects(target, source))
			return CppManagedArrayRecovery.render({
				target: target,
				source: source,
				value: value,
				heap: input.heap,
				destination: destination,
				renderValue: render
			}, indent);
		throw "managed value requires an explicit typed conversion: " + source.getSemanticKey() + " -> " + target.getSemanticKey();
	}

	/** Finish collecting expression steps before returning the exact selected scalar transport. */
	public function renderDirectReturn(value:HxExpr, nativeType:String, indent:String):Array<String> {
		final abi = access.plan.requireFunction(access.owner).abi;
		final type = abi.signature.getFunctionReturn();
		if (abi.result != DirectResult
			|| nativeType != abi.nativeReturnType()
			|| !CppManagedValueTransfer.supports(type, valueType(value), input.casts))
			throw "managed direct return requires its exact typed transport";
		final root = input.temporaryPrefix + "returned";
		final lines = [
			indent + "{",
			indent + "  hxhx::managed::Root<hxhx::managed::Value> " + root + "(" + input.heap + ");"
		];
		for (line in renderTransfer(value, type, root, indent + "  "))
			lines.push(line);
		lines.push(indent + "  return " + CppManagedLeaf.read(type, root + ".get()") + ";");
		lines.push(indent + "}");
		return lines;
	}

	/** Declaration storage comes from exact binding events; native type text cannot choose it. */
	public function renderStatement(statement:HxStmt, indent:String):Array<String> {
		return switch statement {
			case SThrow(value, _):
				// Evaluate once while rooted, then retain that exact value across native unwinding.
				final root = input.temporaryPrefix + "thrown";
				final lines = [
					indent + "{",
					indent + "  hxhx::managed::Root<hxhx::managed::Value> " + root + "(" + input.heap + ");"
				];
				for (line in render(value, root, indent + "  "))
					lines.push(line);
				final carrier = root + "_carrier";
				lines.push(indent + "  auto " + carrier + " = hxhx::managed::ThrownValue(" + input.heap + ", " + root + ".get());");
				if (input.statics != null && input.statics.hasStackContext()) {
					// Publish only after operand evaluation and carrier construction succeed.
					final stack = input.statics.stackAccess(input.heap);
					lines.push(indent + "  " + stack + ".replaceException(" + stack + ".capture());");
				}
				lines.push(indent + "  throw " + carrier + ";");
				lines.push(indent + "}");
				lines;
			case SExpr(expression = ELoweredControl(MapInsert, "", [map, key, value], _), _):
				requireExpression(expression);
				CppManagedMapInsert.render({
					enums: input.enums,
					casts: input.casts,
					classes: input.classes,
					map: map,
					key: key,
					value: value,
					mapType: valueType(map),
					keyType: valueType(key),
					valueType: valueType(value),
					heap: input.heap,
					prefix: input.temporaryPrefix + "insert_",
					renderValue: render
				}, indent);
			case SExpr(expression = ELoweredControl(ArrayAppend, "", [array, value], _), _):
				requireExpression(expression);
				CppManagedArrayAppend.render({
					casts: input.casts,
					array: array,
					value: value,
					arrayType: valueType(array),
					valueType: valueType(value),
					heap: input.heap,
					prefix: input.temporaryPrefix + "append_",
					renderValue: render
				}, indent);
			case SVar(name, _, initializer, _):
				locals.declare({
					name: name,
					casts: input.casts,
					initializer: initializer,
					heap: input.heap,
					indent: indent,
					accepts: acceptsStoredTransfer,
					valueType: valueType,
					render: renderTransfer
				});
			case SExpr(wrapper = EUntyped(inner), position):
				// Shared typing has already applied unchecked source permissions. This
				// wrapper has no runtime effect; keep the exact child and its checks.
				requireExpression(wrapper);
				renderStatement(SExpr(inner, position), indent);
			case SExpr(value = EIdent(_), _):
				// Named-function lowering retains a discarded read after initialization.
				// Preserve the read's checks; no collecting operation follows this copy.
				final selected = field(value);
				if (selected != null && !selected.getField().getIsStatic()) renderDiscard(value, indent); else [
					indent + "static_cast<void>(" + (selected == null ? locals.value(value) : staticRead(selected)) + ");"
				];
			case SExpr(value = ENew(_, _), _) | SExpr(value = EField(_, _), _) | SExpr(value = EArrayAccess(_, _), _):
				renderDiscard(value, indent);
			case SExpr(EBinop(op, target, value), _) if (op == "+=" || op == "-=" || op == "*="):
				renderSelectedAssignment(target, value, null, indent, op.substr(0, 1));
			case SExpr(EBinop("=", target, value), _):
				renderSelectedAssignment(target, value, null, indent);
			case SExpr(value = ECall(_, _), _):
				renderCall(value, null, indent);
			case SExpr(EUnop(op, fixity, target), _) if (op == Increment || op == Decrement):
				renderSelectedUpdate(target, op, fixity, null, indent);
			case SExpr(value, _): throw "managed expression statement requires explicit lowering for " + Type.enumConstructor(value);
			case _: throw "managed statement requires explicit lowering for " + Type.enumConstructor(statement);
		};
	}

	/** Return the owner's selected value type so assignments can validate before emitting effects. */
	public function valueType(value:HxExpr):TyType {
		return applicationType(declaredValueType(value));
	}

	/** Each executable resolves types through its own application without borrowing another body. */
	function applicationType(type:TyType):TyType {
		return switch input.owner {
			case CallableBody(selected): selected.plan.resolveType(type);
			case FieldInitializer(_): input.initializerApplication == null ? type : input.initializerApplication.resolveStorageType(type);
		};
	}

	/** Keep occurrence ownership in the declared view, then apply types at the storage boundary. */
	function declaredValueType(value:HxExpr):TyType {
		final call = instanceCall(value);
		if (CppManagedArrayPush.selects(call)) {
			CppManagedArrayPush.require(call, input.casts);
			return call.getResultType();
		}
		if (CppManagedArrayJoin.selects(call)) {
			CppManagedArrayJoin.require(call, input.callContext);
			return call.getResultType();
		}
		if (CppManagedMapGet.selects(call)) {
			CppManagedMapGet.require(call, input.classes, input.enums);
			return call.getResultType();
		}
		if (call != null) {
			return requireInstanceTarget(call).application.storedResultType();
		}
		final runtime = runtimeType(value);
		if (runtime != null)
			return CppManagedRuntimeType.valueType(runtime, input.classes, input.enums, input.callContext);
		final field = field(value);
		if (field != null)
			return field.getField().getIsStatic()
				|| CppManagedArrayLength.selects(field) ? field.getType() : CppManagedInstanceField.transportType(instanceMember(field));
		return switch value {
			case EParenthesized(inner, _) | EUntyped(inner):
				requireExpression(value);
				valueType(inner);
			case EInt(_): TyType.fromHintText("Int");
			case ENull: TyType.fromHintText('Null');
			case EBool(_): TyType.fromHintText("Bool");
			case EString(_): TyType.fromHintText("String");
			case EThis: access.receiverType(value);
			case ENew(_, _):
				final selected = constructor(value);
				input.classes.requireConstructor(selected, input.callContext);
				input.classes.casts.appliedAbstractStorage(selected.getConstructedType(),
					CppManagedCallContext.resolveType(input.callContext, selected.getConstructedType()));
			case EArrayDecl(_) | EAnon(_, _): aggregate(value).getType();
			case EArrayAccess(array, index):
				requireExpression(value);
				CppManagedArrayRead.elementType(valueType(array), valueType(index));
			case EIdent(name): locals.binding(name).getType();
			case EField(receiver, name):
				requireExpression(value);
				CppManagedRecordRead.fieldType(valueType(receiver), name);
			case EBinop("=", target, _): valueType(target);
			case EBinop(op, target, right) if (op == "+=" || op == "-=" || op == "*="):
				final type = valueType(target);
				CppManagedCompound.requireType(op.substr(0, 1), type, valueType(right));
				type;
			case EBinop(op, left, right):
				// Selectors share one checked view of each operand within this query.
				// Repeating recursive queries in guards multiplies work at every nesting
				// level. A later query still performs all source and occurrence checks.
				final leftType = valueType(left);
				final rightType = valueType(right);
				if (CppManagedNullCompare.selects(op, leftType, rightType)) {
					CppManagedNullCompare.requireTypes(op, leftType, rightType, input.casts);
					TyType.fromHintText("Bool");
				} else if (CppManagedStringConcat.selects(op, leftType,
					rightType)) CppManagedStringConcat.resultType(leftType,
						rightType); else if (CppManagedClassEquality.selects(op, leftType, rightType, input.classes)) {
					requireClassOperation(value);
					TyType.fromHintText("Bool");
				} else if (CppManagedCallableRepresentation.selectsEquality(op, leftType, rightType)
					|| CppManagedClassEquality.selectsInstances(op, leftType, rightType, input.classes, input.casts)
					|| CppManagedClassEquality.selectsOpaqueInstances(op, leftType, rightType, input.classes, input.casts)) {
					TyType.fromHintText("Bool");
				} else if (CppManagedBoolean.supportsEquality(op, leftType,
					rightType)) TyType.fromHintText("Bool"); else if (op == "&&" || op == "||") CppManagedBoolean.resultType(op, leftType,
					rightType); else CppManagedStringEquality.supports(op, leftType,
					rightType) ? TyType.fromHintText("Bool") : CppManagedInteger.resultType(op, leftType, rightType);
			case EUnop(op, _, target) if (op == Increment || op == Decrement):
				CppManagedInteger.resultType("+", valueType(target), TyType.fromHintText("Int"));
			case EUnop(Negate, Prefix, operand): CppManagedInteger.resultType("-", TyType.fromHintText("Int"), valueType(operand));
			case EUnop(LogicalNot, Prefix, operand):
				requireExpression(value);
				CppManagedBoolean.requireCondition(operand, valueType, requireExpression);
				TyType.fromHintText("Bool");
			case ETernary(condition, yes, no):
				CppManagedBoolean.requireCondition(condition, valueType, requireExpression);
				CppManagedValueTransfer.conditionalStorage(valueType(yes), valueType(no));
			case ECall(_, _):
				final call = invocation(value);
				switch call.staticTarget {
					case Downcast(declaration): return CppManagedDowncast.resultType(declaration, call.arguments, valueType, input.classes);
					case _:
				}
				final returned = (call.staticTarget == null ? new CppManagedClosureAbi(valueType(call.callee)) : CppManagedStaticTarget.abi(call.staticTarget))
					.signature.getFunctionReturn();
				call.staticTarget == null ? CppManagedCallableRepresentation.resultStorage(returned) : returned;
			case ELambda(_, _): locals.requireClosure(value).abi.signature;
			case ECast(_, _):
				final conversion = converted(value);
				conversion == null ? valueType(locals.requireAscribedClosure(value)) : conversion.getTargetType();
			case _: throw "managed value requires explicit typed expression lowering for " + Type.enumConstructor(value);
		};
	}

	/** The returned lines complete publication before the caller emits its return or next statement. */
	public function render(value:HxExpr, destination:String, indent:String):Array<String> {
		if (!identifier(destination))
			throw "managed value emission requires a stable destination root";
		final call = instanceCall(value);
		if (CppManagedMapGet.selects(call))
			return CppManagedMapGet.render({
				enums: input.enums,
				classes: input.classes,
				call: call,
				heap: input.heap,
				destination: destination,
				renderValue: render
			}, indent);
		final runtime = runtimeType(value);
		if (runtime != null)
			return CppManagedRuntimeType.render({
				enums: input.enums,
				classes: input.classes,
				occurrence: runtime,
				context: input.callContext,
				heap: input.heap,
				destination: destination,
				renderValue: render
			}, indent);
		final field = field(value);
		if (field != null && field.getField().getIsInline())
			return CppManagedInlineField.render(input, field, destination, indent);
		if (field != null && CppManagedArrayLength.selects(field))
			return CppManagedArrayLength.read({
				occurrence: field,
				heap: input.heap,
				destination: destination,
				renderReceiver: renderInstanceReceiver
			}, indent);
		if (field != null)
			return field.getField().getIsStatic() ? [indent + destination + ".set(" + staticRead(field) + ");"] : CppManagedInstanceField.read({
				occurrence: field,
				member: instanceMember(field),
				heap: input.heap,
				destination: destination,
				renderReceiver: renderInstanceReceiver
			}, indent);
		switch value {
			case EParenthesized(inner, _) | EUntyped(inner):
				requireExpression(value);
				return render(inner, destination, indent);
			case EInt(number):
				return [
					indent + destination + ".set(hxhx::managed::Value::integer(static_cast<std::int32_t>(" + number + "LL)));"
				];
			case ENull:
				return [indent + destination + '.set(hxhx::managed::Value{});'];
			case EBool(flag):
				return [indent + destination + ".set(hxhx::managed::Value::boolean(" + flag + "));"];
			case EThis:
				return [indent + destination + ".set(" + access.receiverValue(value) + ");"];
			case ENew(_, _):
				return CppManagedConstructor.render({
					casts: input.casts,
					occurrence: constructor(value),
					context: input.callContext,
					classes: input.classes,
					resolve: input.resolveConstructor,
					heap: input.heap,
					destination: destination,
					valueType: valueType,
					renderValue: render
				}, indent);
			case EString(text):
				return [
					indent + destination + ".set(hxhx::managed::Value::string(" + CppManagedText.literal(text) + "));"
				];
			case EArrayAccess(array, index):
				requireExpression(value);
				return CppManagedArrayRead.render({
					receiver: array,
					index: index,
					receiverType: valueType(array),
					indexType: valueType(index),
					defaultValue: input.defaultValue,
					heap: input.heap,
					destination: destination,
					renderValue: render
				}, indent);
			case EArrayDecl(_) | EAnon(_, _):
				return CppManagedAggregate.render({
					enums: input.enums,
					casts: input.casts,
					classes: input.classes,
					occurrence: aggregate(value),
					applicationType: applicationType,
					heap: input.heap,
					destination: destination,
					renderValue: render
				}, indent);
			case ECall(_, _):
				return renderCall(value, destination, indent);
			case EField(receiver, name):
				requireExpression(value);
				return CppManagedRecordRead.render({
					receiver: receiver,
					type: valueType(receiver),
					name: name,
					heap: input.heap,
					destination: destination,
					renderValue: render
				}, indent);
			case EBinop(op, target, assigned) if (op == "+=" || op == "-=" || op == "*="):
				return renderSelectedAssignment(target, assigned, destination, indent, op.substr(0, 1));
			case EBinop("=", target, assigned):
				return renderSelectedAssignment(target, assigned, destination, indent);
			case EBinop(op, left, right) if (op == "&&" || op == "||"):
				CppManagedBoolean.resultType(op, valueType(left), valueType(right));
				return CppManagedBoolean.render({
					op: op,
					left: left,
					right: right,
					heap: input.heap,
					destination: destination,
					renderValue: render
				}, indent);
			case EBinop(op, left, right):
				final leftType = valueType(left);
				final rightType = valueType(right);
				final concatenation = CppManagedStringConcat.selects(op, leftType, rightType);
				final strings = CppManagedStringEquality.supports(op, leftType, rightType);
				final nulls = CppManagedNullCompare.selects(op, leftType, rightType);
				final classes = CppManagedClassEquality.selects(op, leftType, rightType, input.classes);
				final callables = CppManagedCallableRepresentation.selectsEquality(op, leftType, rightType);
				final instances = !classes
					&& CppManagedClassEquality.selectsInstances(op, leftType, rightType, input.classes, input.casts);
				final opaqueInstances = !classes
					&& !instances
					&& CppManagedClassEquality.selectsOpaqueInstances(op, leftType, rightType, input.classes, input.casts);
				final booleans = CppManagedBoolean.supportsEquality(op, leftType, rightType);
				if (classes)
					requireClassOperation(value);
				if (nulls)
					CppManagedNullCompare.requireTypes(op, leftType, rightType, input.casts);
				else if (concatenation)
					CppManagedStringConcat.resultType(leftType, rightType);
				else if (!strings && !classes && !booleans && !callables && !instances && !opaqueInstances)
					CppManagedInteger.resultType(op, valueType(left), valueType(right));
				final prefix = destination + "_binary_";
				final a = prefix + "left";
				final b = prefix + "right";
				final lines = [indent + "{",
					indent
					+ "  hxhx::managed::Root<hxhx::managed::Value> "
					+ a
					+ "("
					+ input.heap
					+ "), "
					+ b
					+ "("
					+ input.heap
					+ ");"];
				for (line in render(left, a, indent + "  "))
					lines.push(line);
				for (line in render(right, b, indent + "  "))
					lines.push(line);
				final operation = opaqueInstances ? CppManagedReferenceEquality.computeOpaqueInstance(op, a + '.get()', b + '.get()', destination,
					indent + '  ') : (callables || instances) ? CppManagedReferenceEquality.compute(op, a + '.get()', b + '.get()', destination,
						indent + '  ') : booleans ? CppManagedBoolean.compare(op, leftType, rightType, a + '.get()', b + '.get()', destination,
							indent + '  ') : classes ? CppManagedClassEquality.compute(op, a + '.get()', b + '.get()', destination,
							indent + '  ') : nulls ? CppManagedNullCompare.compute(op, a + '.get()', b + '.get()', destination,
							indent + '  ') : concatenation ? CppManagedStringConcat.compute(leftType, rightType, a + ".get()", b + ".get()", destination,
							indent + "  ") : strings ? CppManagedStringEquality.compute(op, a + ".get()", b + ".get()", destination,
							indent + "  ") : CppManagedInteger.compute(op, leftType, rightType, a + ".get()", b + ".get()", destination, prefix, indent + "  ");
				for (line in operation)
					lines.push(line);
				lines.push(indent + "}");
				return lines;
			case EUnop(op, fixity, target) if (op == Increment || op == Decrement):
				return renderSelectedUpdate(target, op, fixity, destination, indent);
			case EUnop(Negate, Prefix, operand):
				valueType(value);
				final root = destination + "_negated";
				final lines = [
					indent + "{",
					indent + "  hxhx::managed::Root<hxhx::managed::Value> " + root + "(" + input.heap + ");"
				];
				for (line in render(operand, root, indent + "  "))
					lines.push(line);
				for (line in CppManagedInteger.compute("-", TyType.fromHintText("Int"), valueType(operand), "hxhx::managed::Value::integer(0)",
					root
					+ ".get()", destination, root
					+ "_", indent
					+ "  "))
					lines.push(line);
				lines.push(indent + "}");
				return lines;
			case EUnop(LogicalNot, Prefix, operand):
				valueType(value);
				return [
					indent + destination + ".set(hxhx::managed::Value::boolean(!(" + renderControlValue(operand, "bool") + ")));"
				];
			case ETernary(condition, yes, no):
				valueType(value);
				final lines = [indent + "{", indent + "  if (" + renderControlValue(condition, "bool") + ") {"];
				for (line in render(yes, destination, indent + "    "))
					lines.push(line);
				lines.push(indent + "  } else {");
				for (line in render(no, destination, indent + "    "))
					lines.push(line);
				lines.push(indent + "  }");
				lines.push(indent + "}");
				return lines;
			case ECast(_, _):
				final conversion = converted(value);
				return render(conversion == null ? locals.requireAscribedClosure(value) : conversion.getOperand(), destination, indent);
			case EIdent(_):
				return [indent + destination + ".set(" + locals.value(value) + ");"];
			case ELambda(_, _):
				locals.assertChild(value);
				final child = locals.requireClosure(value);
				final link = input.resolve(value);
				if (link == null || link.expression != value || !identifier(link.entrySymbol))
					throw "managed function literal requires its exact emitted entry link";
				final environment = locals.environment(value, link.environmentName);
				final callable = input.temporaryPrefix + "callable";
				final entry = input.temporaryPrefix + "entry";
				final lines = ["{",
					"  hxhx::managed::Root<hxhx::managed::Ref<hxhx::managed::CallablePayload<"
					+ child.abi.nativeSignature()
					+ ">>> "
					+ callable
					+ "("
					+ input.heap
					+ ");",
					"  const auto " + entry + " = &" + link.entrySymbol + ";"
				];
				final construction = environment.renderConstruction({
					heap: input.heap,
					destination: callable,
					entry: entry,
					captures: [
						for (cell in child.getCells())
							{binding: cell.source.binding, reference: locals.cellReference(cell.source.binding)}
					],
					receiver: child.facts.capturesReceiver ? access.receiverReference() : null,
					temporaryPrefix: "hxhx_construct_" + input.temporaryPrefix
				});
				for (line in construction.split("\n"))
					lines.push("  " + line);
				lines.push("  " + destination + ".set(hxhx::managed::Value::managed(" + callable + ".get()));");
				lines.push("}");
				return [for (line in lines) indent + line];
			case _:
				throw "managed rooted expression requires explicit lowering for " + Type.enumConstructor(value);
		}
	}

	/** Field catalogs take precedence over projected local names, as they do for assignment. */
	function renderSelectedUpdate(target:HxExpr, op:HxUnaryOperator, fixity:HxUnaryFixity, destination:Null<String>, indent:String):Array<String> {
		final selected = field(target);
		if (selected != null && !selected.getField().getIsStatic())
			return CppManagedInstanceField.update({
				occurrence: selected,
				member: instanceMember(selected),
				op: op,
				fixity: fixity,
				heap: input.heap,
				prefix: input.temporaryPrefix + (destination == null ? 'discarded' : destination) + '_instance_update_',
				destination: destination,
				renderReceiver: renderInstanceReceiver
			}, indent);
		if (selected != null)
			return CppManagedStaticUpdate.render({
				field: selected,
				storage: input.statics,
				op: op,
				fixity: fixity,
				heap: input.heap,
				prefix: input.temporaryPrefix + (destination == null ? 'discarded' : destination) + '_static_update_',
				destination: destination
			}, indent);
		return switch target {
			case EIdent(name): renderUpdate(access.binding(name), op, fixity, destination, indent);
			case _: throw 'managed update requires an exact mutable local or static field';
		};
	}

	/** Read and write the same selected Int location; postfix publishes the old value. */
	function renderUpdate(binding:TyLocalBinding, op:HxUnaryOperator, fixity:HxUnaryFixity, destination:Null<String>, indent:String):Array<String> {
		CppManagedInteger.resultType("+", access.plan.resolveType(binding.getType()), TyType.fromHintText("Int"));
		final place = access.place(binding);
		final prefix = input.temporaryPrefix + (destination == null ? "discarded" : destination) + "_update_";
		final selected = prefix + "selected";
		final before = prefix + "before";
		final after = prefix + "after";
		final lines = [indent + "{"];
		final read = switch place {
			case Cell(reference):
				lines.push(indent
					+ "  hxhx::managed::Root<hxhx::managed::Ref<hxhx::managed::CellPayload>> "
					+ selected
					+ "("
					+ input.heap
					+ ", "
					+ reference
					+ ");");
				selected + ".get()->read()";
			case LocalRoot(root): root + ".get()";
		};
		lines.push(indent + "  hxhx::managed::Root<hxhx::managed::Value> " + before + "(" + input.heap + ", " + read + ");");
		lines.push(indent + "  hxhx::managed::Root<hxhx::managed::Value> " + after + "(" + input.heap + ");");
		for (line in CppManagedInteger.compute(op == Increment ? "+" : "-", access.plan.resolveType(binding.getType()), TyType.fromHintText("Int"),
			before + ".get()", "hxhx::managed::Value::integer(1)", after, prefix, indent + "  "))
			lines.push(line);
		lines.push(indent + "  " + switch place {
			case Cell(_): selected + ".get()->write(" + after + ".get());";
			case LocalRoot(root): root + ".set(" + after + ".get());";
		});
		if (destination != null)
			lines.push(indent
				+ "  "
				+ destination
				+ ".set("
				+ (fixity == Postfix ? "hxhx::managed::Value::integer("
					+ CppManagedInteger.numericValue(access.plan.resolveType(binding.getType()), before + ".get()")
					+ ")" : after
					+ ".get()")
				+ ");");
		lines.push(indent + "}");
		return lines;
	}

	/** Source calls share the native sequencer after typed operand adaptation. */
	function renderCall(expression:HxExpr, destination:Null<String>, indent:String):Array<String> {
		switch expression {
			case ECall(ESuper, _):
				if (destination != null)
					throw "Void parent constructor call cannot publish a value";
				final occurrence = constructor(expression);
				return CppManagedConstructor.render({
					occurrence: occurrence,
					context: input.callContext,
					classes: input.classes,
					casts: input.casts,
					resolve: input.resolveConstructor,
					heap: input.heap,
					destination: input.temporaryPrefix + "super",
					receiver: access.superReceiverValue(occurrence, input.classes),
					valueType: valueType,
					renderValue: render
				}, indent);
			case _:
		}
		final instance = instanceCall(expression);
		if (CppManagedArrayPush.selects(instance))
			return CppManagedArrayPush.render({
				call: instance,
				casts: input.casts,
				heap: input.heap,
				prefix: input.temporaryPrefix + (destination == null ? 'discarded' : destination) + '_push_',
				destination: destination,
				renderValue: render
			}, indent);
		if (CppManagedArrayJoin.selects(instance))
			return CppManagedArrayJoin.render({
				call: instance,
				context: input.callContext,
				heap: input.heap,
				prefix: input.temporaryPrefix + (destination == null ? 'discarded' : destination) + '_join_',
				destination: destination,
				renderValue: render
			}, indent);
		if (CppManagedMapGet.selects(instance)) {
			if (destination != null)
				return CppManagedMapGet.render({
					enums: input.enums,
					classes: input.classes,
					call: instance,
					heap: input.heap,
					destination: destination,
					renderValue: render
				}, indent);
			final discarded = input.temporaryPrefix + "map_discarded";
			return [
				indent + "{",
				indent + "  hxhx::managed::Root<hxhx::managed::Value> " + discarded + "(" + input.heap + ");"
			].concat(CppManagedMapGet.render({
				enums: input.enums,
				classes: input.classes,
				call: instance,
				heap: input.heap,
				destination: discarded,
				renderValue: render
			}, indent + "  ")).concat([indent + "}"]);
		}
		if (instance != null)
			return CppManagedInstanceCall.render({
				call: instance,
				context: input.callContext,
				target: requireInstanceTarget(instance),
				superReceiver: instance.getCall().receiver.match(ESuper) ? access.superMethodReceiverValue(instance, input.classes) : null,
				classes: input.classes,
				heap: input.heap,
				prefix: input.temporaryPrefix + (destination == null ? 'discarded' : destination) + '_method_',
				destination: destination,
				acceptsStoredTransfer: acceptsStoredTransfer,
				valueType: valueType,
				renderValue: render
			}, indent);
		final call = invocation(expression);
		return CppManagedSourceCall.render({
			acceptsStoredTransfer: acceptsStoredTransfer,
			casts: input.casts,
			classes: input.classes,
			callee: call.staticTarget == null ? Value(call.callee) : Static(call.staticTarget),
			arguments: call.arguments,
			destination: destination,
			heap: input.heap,
			prefix: input.temporaryPrefix,
			renderValue: render,
			valueType: valueType
		}, indent);
	}

	/** The exact executable owns the call before program linkage chooses a native entry. */
	function requireInstanceTarget(call:TypedBackendInstanceCallOccurrence):CppManagedInstanceMethodTarget {
		if (input.classes == null || input.resolveInstance == null)
			throw 'managed instance call requires its program method inventory';
		switch input.owner {
			case CallableBody(selected):
				selected.assertClassStorage(input.classes);
			case FieldInitializer(projection):
				input.classes.assertInitializer(projection);
		}
		final target = input.resolveInstance(call, input.callContext);
		if (target.projection != input.classes.methods.requireInstanceMethod(call, input.callContext))
			throw 'managed instance call selected another program entry';
		return target;
	}

	/** Bind only a checked projected call to the program's exact declaration inventory. */
	function invocation(expression:HxExpr):ManagedSourceInvocation {
		final exact = TypedExactStaticCallSource.decode(expression);
		if (exact != null) {
			requireExpression(expression);
			if (input.resolveStatic == null)
				throw "managed static call requires its program declaration inventory";
			final target = input.resolveStatic(exact.declaration);
			if (target == null || CppManagedStaticTarget.identity(target) != exact.declaration)
				throw "managed static call resolved another declaration";
			if (!staticQualifier(exact.callee))
				throw "managed static callee requires explicit receiver-effect lowering";
			CppManagedStaticTarget.validate(target);
			switch target {
				case Downcast(_):
					requireClassOperation(expression);
				case _:
			}
			return {callee: exact.callee, arguments: exact.arguments, staticTarget: target};
		}
		return switch expression {
			case ECall(callee, arguments):
				switch input.owner {
					case CallableBody(selected): selected.requireLexicalExpression(expression);
					case FieldInitializer(projection): projection.requireExpression(expression);
				}
				{callee: callee, arguments: arguments, staticTarget: null};
			case _: throw "managed invocation requires a call expression";
		};
	}

	static function staticQualifier(expression:HxExpr):Bool {
		return switch expression {
			case EIdent(_): true;
			case EField(owner, _): staticQualifier(owner);
			case _: false;
		};
	}

	/** Construction retains the exact function or initializer occurrence; no source path resolves a class. */
	function constructor(expression:HxExpr):TypedBackendConstructorOccurrence {
		if (input.classes == null)
			throw 'managed construction requires program-owned class storage';
		return switch input.owner {
			case CallableBody(selected): selected.constructor(expression, input.classes);
			case FieldInitializer(projection):
				input.classes.assertInitializer(projection);
				projection.requireConstructor(expression);
		};
	}

	function renderInstanceReceiver(occurrence:TypedBackendFieldOccurrence, destination:String, indent:String):Array<String> {
		return switch occurrence.getExpression() {
			case EField(receiver, _): render(receiver, destination, indent);
			case EIdent(_): [
					indent + destination + '.set(' + access.implicitReceiverValue(occurrence, input.classes) + ');'
				];
			case _: throw 'managed instance field lacks its selected receiver';
		};
	}

	/** Discarding a constructed value or field read must still execute all source effects and checks. */
	function renderDiscard(value:HxExpr, indent:String):Array<String> {
		final root = input.temporaryPrefix + 'discarded_value';
		final lines = [
			indent + '{',
			indent + '  hxhx::managed::Root<hxhx::managed::Value> ' + root + '(' + input.heap + ');'
		];
		for (line in render(value, root, indent + '  '))
			lines.push(line);
		lines.push(indent + '}');
		return lines;
	}

	function field(expression:HxExpr):Null<TypedBackendFieldOccurrence> {
		switch expression {
			case EIdent(_) | EField(_, _):
			case _:
				return null;
		}
		return switch input.owner {
			case CallableBody(selected): selected.field(expression, input.statics, input.classes);
			case FieldInitializer(projection):
				final occurrence = projection.findField(expression);
				if (occurrence == null) null; else {
					projection.requireExpression(expression);
					if (occurrence.getField().getIsStatic()) {
						if (input.statics == null)
							throw 'managed static initializer read requires program storage';
						input.statics.assertInitializer(projection);
						if (occurrence.getField().getIsInline())
							input.statics.inlineInitializer(occurrence);
						else
							input.statics.member(occurrence);
					} else {
						if (input.classes == null)
							throw 'managed instance initializer read requires program storage';
						input.classes.assertInitializer(projection);
						if (CppManagedArrayLength.selects(occurrence))
							CppManagedArrayLength.require(occurrence);
					}
					occurrence;
				}
		};
	}

	function staticRead(field:TypedBackendFieldOccurrence):String
		return input.heap + ".requireStatic<" + input.statics.nativeName + ">()->" + input.statics.member(field) + ".read()";

	/** Resolve the applied receiver through exact expressions or lexical receiver facts, never field-owner spelling. */
	function instanceMember(field:TypedBackendFieldOccurrence):backend.cpp.CppManagedClassStorage.CppManagedInstanceMember {
		final receiver = switch field.getReceiver() {
			case ValueReceiver:
				switch field.getExpression() {
					case EField(value, _): valueType(value);
					case _: throw "managed instance field lost its exact receiver expression";
				}
			case ImplicitOwner: access.implicitReceiverType(field, input.classes);
			case TypeQualifier: throw "managed instance field cannot use a type qualifier";
		};
		final semanticType = switch input.owner {
			case CallableBody(selected): selected.plan.resolveSemanticType(field.getType());
			case FieldInitializer(_): input.initializerApplication == null ? field.getType() : input.initializerApplication.resolveType(field.getType());
		};
		return input.classes.member(field, receiver, semanticType);
	}

	/** Static storage remains rooted through RHS effects; failed evaluation must leave its old value intact. */
	function renderSelectedAssignment(target:HxExpr, value:HxExpr, destination:Null<String>, indent:String, ?compoundOp:String):Array<String> {
		switch target {
			case EThis:
				return CppManagedReceiverWrite.render({
					reference: access.writableReceiver(target),
					type: access.receiverType(target),
					value: value,
					valueType: valueType(value),
					casts: input.casts,
					compoundOp: compoundOp,
					heap: input.heap,
					prefix: input.temporaryPrefix + (destination == null ? 'discarded' : destination) + '_receiver_write_',
					destination: destination,
					renderValue: render
				}, indent);
			case EArrayAccess(array, index):
				requireExpression(target);
				if (compoundOp != null)
					throw 'managed array compound assignment requires explicit read-modify-write lowering';
				return CppManagedArrayWrite.render({
					receiver: array,
					index: index,
					value: value,
					receiverType: valueType(array),
					indexType: valueType(index),
					valueType: valueType(value),
					casts: input.casts,
					defaultValue: input.defaultValue,
					heap: input.heap,
					prefix: input.temporaryPrefix + (destination == null ? 'discarded' : destination) + '_array_write_',
					destination: destination,
					renderValue: render
				}, indent);
			case _:
		}
		final field = field(target);
		if (field == null)
			return switch target {
				case EIdent(name): renderAssignment(locals.binding(name), value, destination, indent, compoundOp);
				case _: throw "managed assignment requires an exact mutable place";
			};
		if (!field.getField().getIsStatic())
			return CppManagedInstanceField.write({
				casts: input.casts,
				occurrence: field,
				member: instanceMember(field),
				value: value,
				valueType: valueType(value),
				allowFinal: switch input.owner {
					case CallableBody(selected): selected.allowsFinalFieldWrite(field);
					case _: false;
				},
				heap: input.heap,
				prefix: input.temporaryPrefix + (destination == null ? 'discarded' : destination) + '_field_',
				destination: destination,
				compoundOp: compoundOp,
				renderReceiver: renderInstanceReceiver,
				renderValue: render
			}, indent);
		final type = valueType(value);
		if (compoundOp != null)
			CppManagedCompound.requireType(compoundOp, field.getType(), type);
		if (compoundOp == null && !CppManagedValueTransfer.supports(field.getType(), type, input.casts))
			throw "managed static assignment requires an explicit typed conversion";
		final member = input.statics.member(field, true);
		final prefix = input.temporaryPrefix + (destination == null ? "discarded" : destination) + "_static_";
		final selected = prefix + "selected";
		final assigned = prefix + "assigned";
		final lines = [indent + "{",
			indent
			+ "  const auto "
			+ selected
			+ " = "
			+ input.heap
			+ ".requireStatic<"
			+ input.statics.nativeName
			+ ">();",
			indent + "  hxhx::managed::Root<hxhx::managed::Value> " + assigned + "(" + input.heap + ");"
		];
		// Save a rooted value before RHS effects can replace the selected storage.
		final before = prefix + "before";
		if (compoundOp != null) {
			final read = selected + "->" + member + ".read()";
			lines.push(indent + "  hxhx::managed::Root<hxhx::managed::Value> " + before + "(" + input.heap + ", " + read + ");");
		}
		for (line in render(value, assigned, indent + "  "))
			lines.push(line);
		if (compoundOp == null)
			for (line in CppManagedValueTransfer.convertRoot(field.getType(), type, assigned, indent + "  ", input.casts))
				lines.push(line);
		if (compoundOp != null)
			for (line in CppManagedCompound.compute(compoundOp, field.getType(), type, before + ".get()", assigned + ".get()", assigned, prefix + "compound_",
				indent + "  "))
				lines.push(line);
		lines.push(indent + "  " + selected + "->" + member + ".write(" + assigned + ".get());");
		if (destination != null)
			lines.push(indent + "  " + destination + ".set(" + assigned + ".get());");
		lines.push(indent + "}");
		return lines;
	}

	/** Select and retain the place before RHS effects; publish the result only after the write succeeds. */
	function renderAssignment(binding:TyLocalBinding, value:HxExpr, destination:Null<String>, indent:String, ?compoundOp:String):Array<String> {
		final sourceType = valueType(value);
		if (compoundOp != null)
			CppManagedCompound.requireType(compoundOp, applicationType(binding.getType()), sourceType);
		if (compoundOp == null && !CppManagedValueTransfer.supports(applicationType(binding.getType()), sourceType, input.casts))
			throw "managed assignment requires an explicit typed conversion";
		final place = locals.place(binding);
		// Deriving names from the destination keeps nested assignment blocks distinct.
		final prefix = input.temporaryPrefix + (destination == null ? "discarded" : destination) + "_";
		final selected = prefix + "selected";
		final assigned = prefix + "assigned";
		final lines = [indent + "{"];
		switch place {
			case Cell(reference):
				lines.push(indent
					+ "  hxhx::managed::Root<hxhx::managed::Ref<hxhx::managed::CellPayload>> "
					+ selected
					+ "("
					+ input.heap
					+ ", "
					+ reference
					+ ");");
			case LocalRoot(_):
		}
		lines.push(indent + "  hxhx::managed::Root<hxhx::managed::Value> " + assigned + "(" + input.heap + ");");
		// Save a rooted value before RHS effects can replace the selected storage.
		final before = prefix + "before";
		if (compoundOp != null) {
			final read = switch place {
				case Cell(_): selected + ".get()->read()";
				case LocalRoot(root): root + ".get()";
			};
			lines.push(indent + "  hxhx::managed::Root<hxhx::managed::Value> " + before + "(" + input.heap + ", " + read + ");");
		}
		for (line in render(value, assigned, indent + "  "))
			lines.push(line);
		if (compoundOp == null)
			for (line in CppManagedValueTransfer.convertRoot(applicationType(binding.getType()), sourceType, assigned, indent + "  ", input.casts))
				lines.push(line);
		if (compoundOp != null)
			for (line in CppManagedCompound.compute(compoundOp, applicationType(binding.getType()), sourceType, before
				+ ".get()", assigned
				+ ".get()",
				assigned, prefix
				+ "compound_", indent
				+ "  "))
				lines.push(line);
		lines.push(indent + "  " + switch place {
			case Cell(_): selected + ".get()->write(" + assigned + ".get());";
			case LocalRoot(root): root + ".set(" + assigned + ".get());";
		});
		if (destination != null)
			lines.push(indent + "  " + destination + ".set(" + assigned + ".get());");
		lines.push(indent + "}");
		return lines;
	}

	static function identifier(value:Null<String>):Bool
		return value != null && ~/^[A-Za-z_][A-Za-z0-9_]*$/.match(value);
}
