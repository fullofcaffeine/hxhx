/**
	Stable structural tags for typed expressions.

	Payloads live on `TypedExpr` itself. Keeping this enum payload-free lets the
	OCaml bootstrap target emit the recursively typed node as one record instead
	of creating a module or declaration cycle between a node and its kind.
**/
enum TypedExprTag {
	Parenthesized;
	NullValue;
	BoolValue;
	StringValue;
	IntValue;
	FloatValue;
	EnumValue;
	RuntimeTypeValue;
	RuntimeTypeTest;
	ThisValue;
	SuperValue;
	LocalRead;
	NameRead;
	FieldRead;
	NullSafeFieldRead;
	Call;
	TargetScope;
	FeatureDefinition;
	FeatureSelection;
	MacroExpr;
	MacroType;
	Lambda;
	SwitchExpr;
	NewValue;
	Unary;
	Binary;
	Assign;
	CompoundAssign;
	Ternary;
	Anonymous;
	ArrayComprehension;
	ArrayAppend;
	MapInsert;
	ArrayDecl;
	ArrayAccess;
	Range;
	FixedRange;
	Cast;
	Untyped;
	Opaque;
	Block;
	Temporary;
	ReturnExpr;
	VariableDeclarations;
	VariableDeclaration;
	WhileExpr;
	BreakExpr;
	ContinueExpr;
	SourceGroup;
	SourceFunction;
	ControlRegion;
	SourceIf;
	ThrowExpr;
	ControlBranch;
	ControlWhile;
	SourceFor;
	ControlFor;
	ControlSwitch;
	SourceTry;
	ControlTry;
	PrivateAccess;
}

/**
	One semantically typed expression node.

	Every child is stored structurally in `expressions`; no parsed expression can
	hide beneath a typed parent. Scalar payloads use dedicated fields selected by
	`tag`. Static factories are the only construction API so each shape has one
	canonical layout.

	`position` is null when the parser did not retain a position for this exact
	nested expression. Callers must not substitute a parent position and pretend
	it is precise. The semantic type is always present; unresolved bootstrap cases
	use `TyType.unknown()` explicitly.
**/
class TypedExpr {
	/** Statement operands keep their exact API owner and do not acquire runtime argument bindings. */
	public static function targetScope(declaration:TyDeclarationInfo, body:TypedExpr, position:Null<HxPos>):TypedExpr {
		final result = new TypedExpr(TargetScope, body.getType().isNoNormalCompletion() ? TyType.noNormalCompletion() : TyType.fromHintText("Void"), position,
			[], [body], null, false, 0, 0.0, declaration);
		TypedTargetScope.kind(result);
		return result;
	}

	final tag:TypedExprTag;
	final type:TyType;
	final position:Null<HxPos>;
	final texts:Array<String>;
	final expressions:Array<TypedExpr>;
	final patterns:Array<HxSwitchPattern>;
	final boolValue:Bool;
	final intValue:Int;
	final floatValue:Float;
	final declaration:Null<TyDeclarationInfo>;
	final unaryOperator:Null<HxUnaryOperator>;
	final unaryFixity:Null<HxUnaryFixity>;
	final opaqueKind:Null<TypedOpaqueExprKind>;
	final fieldInfo:Null<TyFieldInfo>;
	final localBindings:Array<TyLocalBinding>;
	final extensionProvider:Null<TyNominalTypeId>;
	final runtimeTypeTarget:Null<TypedRuntimeTypeTarget>;
	final catchUses:Array<TypedCatchUse>;
	final lambdaSignature:Null<HxLambdaSignature>;
	final sourceFunction:Null<HxSourceFunction>;
	final controlTarget:Null<TyControlTarget>;
	final sourceCatches:Array<HxSourceCatch>;
	final constructorApplication:Null<TypedConstructorApplication>;
	final argumentBinding:Null<TyCallArgumentBinding>;
	final namedArguments:Null<TypedNamedCallBinding>;

	function new(tag:TypedExprTag, type:TyType, position:Null<HxPos>, ?texts:Array<String>, ?expressions:Array<TypedExpr>, ?patterns:Array<HxSwitchPattern>,
			boolValue:Bool = false, intValue:Int = 0, floatValue:Float = 0.0, ?declaration:TyDeclarationInfo, ?unaryOperator:HxUnaryOperator,
			?unaryFixity:HxUnaryFixity, ?opaqueKind:TypedOpaqueExprKind, ?fieldInfo:TyFieldInfo, ?localBindings:Array<TyLocalBinding>,
			?extensionProvider:TyNominalTypeId, ?runtimeTypeTarget:TypedRuntimeTypeTarget, ?catchUses:Array<TypedCatchUse>,
			?lambdaSignature:HxLambdaSignature, ?sourceFunction:HxSourceFunction, ?controlTarget:TyControlTarget, ?sourceCatches:Array<HxSourceCatch>,
			?constructorApplication:TypedConstructorApplication, ?argumentBinding:TyCallArgumentBinding, ?namedArguments:TypedNamedCallBinding) {
		if (declaration != null)
			declaration.requireSupportedImplementation();
		if (constructorApplication != null) {
			constructorApplication.getDeclaration().requireSupportedImplementation();
			if (declaration != null)
				throw "constructor application requires an unambiguous construction node";
			if (tag == NewValue) {
				constructorApplication.assertResult(type);
			} else if (tag == Call
				&& expressions != null
				&& expressions.length > 0
				&& expressions[0].getTag() == SuperValue
				&& type.isVoid()) {
				constructorApplication.assertResult(expressions[0].getType());
			} else {
				throw "constructor application requires allocation or a Void parent call";
			}
		}
		if (controlTarget != null) {
			switch tag {
				case SourceFunction | ReturnExpr | ControlRegion:
					if (controlTarget.getKind() != Function)
						throw "typed function control requires a function target";
				case WhileExpr | ControlWhile | SourceFor | ControlFor | BreakExpr | ContinueExpr:
					if (controlTarget.getKind() != Loop)
						throw "typed loop control requires a loop target";
				case _:
					throw "ordinary typed expression cannot carry a control target";
			}
		}
		if (tag == SourceFunction) {
			if (sourceFunction == null || expressions == null || expressions.length == 0)
				throw "typed source function requires facts and a body child";
			sourceFunction.assertDefaultCount(expressions.length - 1);
		}
		this.tag = tag;
		this.type = type == null ? TyType.unknown() : type;
		this.position = position;
		this.texts = texts == null ? [] : texts.copy();
		this.expressions = expressions == null ? [] : expressions.copy();
		this.patterns = patterns == null ? [] : patterns.copy();
		this.boolValue = boolValue;
		this.intValue = intValue;
		this.floatValue = floatValue;
		this.declaration = declaration;
		this.unaryOperator = unaryOperator;
		this.unaryFixity = unaryFixity;
		this.opaqueKind = opaqueKind;
		this.fieldInfo = fieldInfo;
		this.localBindings = localBindings == null ? [] : localBindings.copy();
		this.extensionProvider = extensionProvider;
		this.runtimeTypeTarget = runtimeTypeTarget;
		this.catchUses = catchUses == null ? [] : catchUses.copy();
		this.lambdaSignature = lambdaSignature;
		this.sourceFunction = sourceFunction;
		this.controlTarget = controlTarget;
		this.sourceCatches = sourceCatches == null ? [] : sourceCatches.copy();
		this.constructorApplication = constructorApplication;
		this.argumentBinding = argumentBinding;
		this.namedArguments = namedArguments;
		if (tag == TargetScope)
			TypedTargetScope.kind(this);
		assertArgumentBinding();
	}

	public static function nullValue(type:TyType, position:Null<HxPos>):TypedExpr
		return new TypedExpr(NullValue, type, position);

	public static function boolLiteral(value:Bool, type:TyType, position:Null<HxPos>):TypedExpr
		return new TypedExpr(BoolValue, type, position, null, null, null, value);

	public static function stringLiteral(value:String, type:TyType, position:Null<HxPos>):TypedExpr
		return new TypedExpr(StringValue, type, position, [value == null ? "" : value]);

	public static function intLiteral(value:Int, type:TyType, position:Null<HxPos>):TypedExpr
		return new TypedExpr(IntValue, type, position, null, null, null, false, value);

	public static function floatLiteral(value:Float, type:TyType, position:Null<HxPos>):TypedExpr
		return new TypedExpr(FloatValue, type, position, null, null, null, false, 0, value);

	public static function enumValue(name:String, type:TyType, position:Null<HxPos>):TypedExpr
		return new TypedExpr(EnumValue, type, position, [name]);

	/** Carries a class value without reconstructing its identity from source text. */
	public static function runtimeTypeValue(target:TypedRuntimeTypeTarget, position:Null<HxPos>):TypedExpr
		return new TypedExpr(RuntimeTypeValue, target.getValueType(), position, null, null, null, false, 0, 0.0, null, null, null, null, null, null, null,
			target);

	/** Evaluates only the value child; the target was selected in the type namespace. */
	public static function runtimeTypeTest(value:TypedExpr, target:TypedRuntimeTypeTarget, position:Null<HxPos>):TypedExpr
		return new TypedExpr(RuntimeTypeTest, TyType.fromHintText("Bool"), position, null, [value], null, false, 0, 0.0, null, null, null, null, null, null,
			null, target);

	public function getRuntimeTypeTarget():Null<TypedRuntimeTypeTarget>
		return runtimeTypeTarget;

	public static function thisValue(type:TyType, position:Null<HxPos>):TypedExpr
		return new TypedExpr(ThisValue, type, position);

	/** Preserve source grouping without allocating a local binding or control destination. */
	public static function parenthesized(inner:TypedExpr, position:Null<HxPos>):TypedExpr
		return new TypedExpr(Parenthesized, inner.getType(), position, null, [inner]);

	/** Keep source access permission until shared access selection consumes it. */
	public static function privateAccess(inner:TypedExpr, position:Null<HxPos>):TypedExpr
		return new TypedExpr(PrivateAccess, inner.getType(), position, null, [inner]);

	public static function superValue(type:TyType, position:Null<HxPos>):TypedExpr
		return new TypedExpr(SuperValue, type, position);

	public static function localRead(name:String, type:TyType, position:Null<HxPos>, ?binding:TyLocalBinding):TypedExpr
		return new TypedExpr(LocalRead, type, position, [name], null, null, false, 0, 0.0, null, null, null, null, null, binding == null ? [] : [binding]);

	/**
		Preserve a non-local name and, when typing selected a current-class field,
		carry that exact field with the read. This distinguishes a value such as
		`root:TreeNode` from the type name `TreeNode`; both have the same nominal
		result type, but only the latter may be rewritten through an import alias.
	**/
	public static function nameRead(name:String, type:TyType, position:Null<HxPos>, ?fieldInfo:TyFieldInfo, requiresOwnerQualification:Bool = false):TypedExpr
		return new TypedExpr(NameRead, type, position, [name], null, null, requiresOwnerQualification, 0, 0.0, null, null, null, null, fieldInfo);

	public static function fieldRead(object:TypedExpr, field:String, type:TyType, position:Null<HxPos>, ?fieldInfo:TyFieldInfo):TypedExpr
		return new TypedExpr(FieldRead, type, position, [field], [object], null, false, 0, 0.0, null, null, null, null, fieldInfo);

	/** Shared property lowering has selected real backing storage for this exact field occurrence. */
	public function withPropertyStorageAccess():TypedExpr {
		if ((tag != NameRead && tag != FieldRead) || fieldInfo == null || !fieldInfo.getHasStorage())
			throw "property backing access requires an exact stored field";
		return new TypedExpr(tag, type, position, texts, expressions, patterns, boolValue, 2, floatValue, declaration, unaryOperator, unaryFixity, opaqueKind,
			fieldInfo, localBindings, extensionProvider, runtimeTypeTarget, catchUses, lambdaSignature, sourceFunction, controlTarget, sourceCatches,
			constructorApplication, argumentBinding);
	}

	public function getHasPropertyStorageAccess():Bool
		return (tag == NameRead || tag == FieldRead) && intValue == 2 && fieldInfo != null;

	/**
		The typer found an abstract receiver but no declared member. Under explicit
		untyped checking, a call retains this receiver and defers lookup until after
		argument statements. Unknown class fields do not have this call order.
		This fact grants no permission to bypass ordinary type checking.
	 */
	public static function unresolvedAbstractFieldRead(object:TypedExpr, field:String, type:TyType, position:Null<HxPos>):TypedExpr
		return new TypedExpr(FieldRead, type, position, [field], [object], null, false, 1);

	public function hasUnresolvedAbstractReceiver():Bool
		return tag == FieldRead && intValue == 1 && declaration == null && fieldInfo == null;

	/** Keep method-value identity independently of its local spelling or a later call. */
	public static function staticMethodRead(name:String, declaration:TyDeclarationInfo, type:TyType, position:Null<HxPos>, qualifyOwner:Bool,
			?object:TypedExpr):TypedExpr {
		if (declaration == null || !declaration.getIsStatic() || declaration.getIsEnumConstructor())
			throw "static method value requires an exact method declaration";
		return new TypedExpr(object == null ? NameRead : FieldRead, type, position, [name], object == null ? [] : [object], null, qualifyOwner, 0, 0.0,
			declaration);
	}

	/** Keep the selected instance declaration and its evaluated receiver for later binding. */
	public static function instanceMethodRead(object:TypedExpr, name:String, declaration:TyDeclarationInfo, type:TyType, position:Null<HxPos>):TypedExpr {
		if (object == null || declaration == null || declaration.getIsStatic() || declaration.getIsEnumConstructor())
			throw "instance method value requires an exact declaration and receiver";
		return new TypedExpr(FieldRead, type, position, [name], [object], null, false, 0, 0.0, declaration);
	}

	/** Preserve a null-safe field read until shared target lowering selects its evaluation schedule. **/
	public static function nullSafeFieldRead(object:TypedExpr, field:String, type:TyType, position:Null<HxPos>):TypedExpr
		return new TypedExpr(NullSafeFieldRead, type, position, [field], [object]);

	public static function call(callee:TypedExpr, arguments:Array<TypedExpr>, declaration:Null<TyDeclarationInfo>, type:TyType, position:Null<HxPos>,
			requiresOwnerQualification:Bool = false, ?extensionProvider:TyNominalTypeId):TypedExpr
		return new TypedExpr(Call, type, position, null, [callee].concat(arguments == null ? [] : arguments), null, requiresOwnerQualification, 0, 0.0,
			declaration, null, null, null, null, null, extensionProvider);

	/** A retained definition enables its name at compilation time and evaluates its operand at runtime. */
	public static function featureDefinition(name:String, value:TypedExpr, position:Null<HxPos>):TypedExpr {
		if (name == null || value == null)
			throw "feature definition requires a literal name and operand";
		return new TypedExpr(FeatureDefinition, value.getType(), position, [name], [value]);
	}

	/**
		Keep both authored branches until program-owned feature selection chooses one.
		The result is Dynamic because recognition occurs only inside an explicit untyped
		boundary; neither a callable declaration nor a concrete branch result is invented.
	 */
	public static function featureSelection(name:String, selected:TypedExpr, fallback:Null<TypedExpr>, position:Null<HxPos>):TypedExpr {
		if (name == null || selected == null)
			throw "feature selection requires a literal name and selected branch";
		return new TypedExpr(FeatureSelection, TyType.fromHintText("Dynamic"), position, [name], fallback == null ? [selected] : [selected, fallback]);
	}

	/** Retain shared argument checking on a function value without changing its source children. */
	public static function functionValueCall(callee:TypedExpr, arguments:Array<TypedExpr>, type:TyType, position:Null<HxPos>,
			?selectedBinding:TyCallArgumentBinding):TypedExpr {
		final kinds = operandKinds(arguments);
		final binding = selectedBinding != null ? selectedBinding : TyCallArgumentBinding.require(TyCallableSignature.fromFunctionValue(callee.getType()),
			operandTypes(arguments, kinds), kinds, Unchecked);
		binding.assertCurrent(callee.getType(), operandTypes(arguments, kinds), kinds);
		return new TypedExpr(Call, type, position, null, [callee].concat(arguments), null, false, 0, 0.0, null, null, null, null, null, null, null, null,
			null, null, null, null, null, null, binding);
	}

	/** Read the existing explicit spread intrinsic; ordinary function calls remain value operands. */
	@:allow(TypedCallExpectedArguments)
	@:allow(TypedBackendConstructorOccurrence)
	@:allow(TypedNamedCallPlan)
	@:allow(TypedMultiTypeConstruction)
	static function operandKinds(arguments:Array<TypedExpr>):Array<TyCallAlignment.TyCallOperandKind> {
		return [
			for (argument in arguments) {
				final children = argument.getExpressions();
				argument.getTag() == Call
			&& children.length == 2
			&& children[0].getTag() == NameRead
			&& children[0].getTexts().length == 1
			&& children[0].getTexts()[0] == "__hxhx_spread" ? Spread : Value;
			}
		];
	}

	@:allow(TypedCallExpectedArguments)
	@:allow(TypedBackendConstructorOccurrence)
	@:allow(TypedNamedCallPlan)
	@:allow(TypedMultiTypeConstruction)
	static function operandTypes(arguments:Array<TypedExpr>, kinds:Array<TyCallAlignment.TyCallOperandKind>):Array<TyType>
		return [
			for (index in 0...arguments.length)
				kinds[index] == Spread ? arguments[index].getExpressions()[1].getType() : arguments[index].getType()
		];

	public function getArgumentBinding():Null<TyCallArgumentBinding>
		return argumentBinding;

	public function getNamedArguments():Null<TypedNamedCallBinding>
		return namedArguments;

	/** Attach the selected declaration's final argument facts after source conversions are complete. */
	public function withNamedArguments(binding:TypedNamedCallBinding):TypedExpr
		return new TypedExpr(tag, type, position, texts, expressions, patterns, boolValue, intValue, floatValue, declaration, unaryOperator, unaryFixity,
			opaqueKind, fieldInfo, localBindings, extensionProvider, runtimeTypeTarget, catchUses, lambdaSignature, sourceFunction, controlTarget,
			sourceCatches, constructorApplication, argumentBinding, binding);

	/** Reject stale argument facts at construction and whenever a typed rewrite rebuilds this node. */
	public function assertArgumentBinding():Void {
		if (namedArguments != null) {
			if (tag != Call || declaration == null || argumentBinding != null || expressions.length == 0)
				throw "named argument binding attached to a different call category";
			final values = expressions.slice(1);
			final kinds = operandKinds(values);
			namedArguments.assertCurrent(declaration, extensionProvider, operandTypes(values, kinds), kinds, type);
		}
		if (argumentBinding == null)
			return;
		if (tag != Call || declaration != null || extensionProvider != null || expressions.length == 0)
			throw "function-value argument binding attached to a different call category";
		final arguments = expressions.slice(1);
		final kinds = operandKinds(arguments);
		argumentBinding.assertCurrent(expressions[0].getType(), operandTypes(arguments, kinds), kinds);
		if (type.getSemanticKey() != argumentBinding.getFunctionType().getFunctionReturn().getSemanticKey())
			throw "function-value argument binding has a stale result type";
	}

	/** Preserve a nested source return until macro expansion consumes it or emission rejects it. **/
	public static function returnExpr(expression:Null<TypedExpr>, type:TyType, position:Null<HxPos>):TypedExpr
		return new TypedExpr(ReturnExpr, type, position, null, expression == null ? [] : [expression]);

	/** Preserve a source-level declaration as a structural child of an expression-level declaration list. **/
	public static function variableDeclaration(name:String, typeHint:String, initializer:Null<TypedExpr>, isFinal:Bool, isStatic:Bool, type:TyType,
			position:Null<HxPos>, ?binding:TyLocalBinding):TypedExpr
		return new TypedExpr(VariableDeclaration, type, position, [name == null ? "" : name, typeHint == null ? "" : typeHint],
			initializer == null ? [] : [initializer], null, isFinal, isStatic ? 1 : 0, 0.0, null, null, null, null, null, binding == null ? [] : [binding]);

	/** Preserve the ordered declarations from one expression-level `var` or `final` form. **/
	public static function variableDeclarations(declarations:Array<TypedExpr>, type:TyType, position:Null<HxPos>):TypedExpr
		return new TypedExpr(VariableDeclarations, type, position, null, declarations);

	/** Preserve an expression-position while loop until macro expansion consumes it or emission rejects it. **/
	public static function whileExpr(condition:TypedExpr, body:Array<TypedExpr>, bodyIsBlock:Bool, type:TyType, position:Null<HxPos>,
			loopKind:HxWhileKind):TypedExpr
		return new TypedExpr(WhileExpr, type, position, null, [condition].concat(body == null ? [] : body), null, bodyIsBlock, loopKind == DoWhile ? 1 : 0);

	/** Authored iteration retains exact local bindings and its enclosing control destination. */
	public static function sourceFor(binding:HxForBinding, iterable:TypedExpr, body:TypedExpr, type:TyType, position:Null<HxPos>,
			bindings:Array<TyLocalBinding>, target:Null<TyControlTarget>):TypedExpr
		return new TypedExpr(SourceFor, type, position, HxForBinding.names(binding), [iterable, body], null, false, 0, 0.0, null, null, null, null, null,
			bindings).withControlTarget(target);

	/** Ordered catch declarations and all bodies remain visible to typed replay and macro syntax. */
	public static function sourceTry(catches:Array<HxSourceCatch>, bodies:Array<TypedExpr>, type:TyType, position:Null<HxPos>,
			bindings:Array<TyLocalBinding>):TypedExpr
		return new TypedExpr(SourceTry, type, position, null, bodies, null, false, 0, 0.0, null, null, null, null, null, bindings, null, null, null, null,
			null, null, catches);

	public function getSourceCatches():Array<HxSourceCatch>
		return sourceCatches.copy();

	/** Executable handlers retain their typed declarations while each body becomes a lexical region. */
	public static function controlTry(catches:Array<HxSourceCatch>, bodies:Array<TypedExpr>, type:TyType, position:Null<HxPos>,
			bindings:Array<TyLocalBinding>):TypedExpr
		return new TypedExpr(ControlTry, type, position, null, bodies, null, false, 0, 0.0, null, null, null, null, null, bindings, null, null, null, null,
			null, null, catches);

	/** Derived iteration keeps exact declarations while replacing only the authored body with a lexical region. */
	public static function controlFor(binding:HxForBinding, iterable:TypedExpr, body:TypedExpr, position:Null<HxPos>, bindings:Array<TyLocalBinding>,
			target:TyControlTarget):TypedExpr
		return new TypedExpr(ControlFor, TyType.fromHintText("Void"), position, HxForBinding.names(binding), [iterable, body], null, false, 0, 0.0, null,
			null, null, null, null, bindings).withControlTarget(target);

	/** Preserve nested loop exit as an explicit no-normal-completion expression. **/
	public static function breakExpr(position:Null<HxPos>):TypedExpr
		return new TypedExpr(BreakExpr, TyType.noNormalCompletion(), position);

	/** Preserve nested loop continuation as an explicit no-normal-completion expression. **/
	public static function continueExpr(position:Null<HxPos>):TypedExpr
		return new TypedExpr(ContinueExpr, TyType.noNormalCompletion(), position);

	public static function macroExpr(expression:TypedExpr, wrappers:Array<String>, type:TyType, position:Null<HxPos>):TypedExpr
		return new TypedExpr(MacroExpr, type, position, wrappers, [expression]);

	public static function macroType(typeText:String, type:TyType, position:Null<HxPos>):TypedExpr
		return new TypedExpr(MacroType, type, position, [typeText]);

	public static function lambda(arguments:Array<String>, body:TypedExpr, type:TyType, position:Null<HxPos>, ?bindings:Array<TyLocalBinding>,
			?signature:HxLambdaSignature):TypedExpr
		return new TypedExpr(Lambda, type, position, arguments, [body], null, false, 0, 0.0, null, null, null, null, null, bindings, null, null, null,
			signature);

	/** Authored braces retain their ordered children and lexical scope through typed rebuilds. */
	public static function sourceGroup(children:Array<TypedExpr>, type:TyType, position:Null<HxPos>):TypedExpr
		return new TypedExpr(SourceGroup, type, position, null, children);

	/** Two children mean no else was authored; an explicit null else is a third child. */
	public static function sourceIf(condition:TypedExpr, whenTrue:TypedExpr, whenFalse:Null<TypedExpr>, type:TyType, position:Null<HxPos>):TypedExpr
		return new TypedExpr(SourceIf, type, position, null, whenFalse == null ? [condition, whenTrue] : [condition, whenTrue, whenFalse]);

	/** Throw evaluates its operand and cannot complete with an ordinary expression value. */
	public static function throwExpr(value:TypedExpr, position:Null<HxPos>):TypedExpr
		return new TypedExpr(ThrowExpr, TyType.noNormalCompletion(), position, null, [value]);

	/** A lowered branch selects one lexical statement region, without an expression wrapper. */
	public static function controlBranch(condition:TypedExpr, whenTrue:TypedExpr, whenFalse:Null<TypedExpr>, type:TyType, position:Null<HxPos>):TypedExpr
		return new TypedExpr(ControlBranch, type, position, null, whenFalse == null ? [condition, whenTrue] : [condition, whenTrue, whenFalse]);

	/** A repeated condition and one lexical body, after shared source-control lowering. */
	public static function controlWhile(condition:TypedExpr, body:TypedExpr, position:Null<HxPos>, target:TyControlTarget, loopKind:HxWhileKind):TypedExpr
		return new TypedExpr(ControlWhile, TyType.fromHintText("Void"), position, null, [condition, body], null, false,
			loopKind == DoWhile ? 1 : 0).withControlTarget(target);

	/** Decode the loop-only scalar payload; no ordinary expression can supply a loop kind. */
	public function getWhileKind():HxWhileKind {
		if (tag != WhileExpr && tag != ControlWhile)
			throw "only a typed while loop carries a loop kind";
		return switch intValue {
			case 0: Normal;
			case 1: DoWhile;
			case _: throw "invalid typed while loop kind";
		};
	}

	/** A lowered statement region establishes a function target or preserves a lexical scope. */
	public static function controlRegion(children:Array<TypedExpr>, type:TyType, position:Null<HxPos>, ?target:TyControlTarget):TypedExpr
		return new TypedExpr(ControlRegion, type, position, null, children, null, false, 0, 0.0, null, null, null, null, null, null, null, null, null, null,
			null, target);

	/** The first child is the original body; later children are defaults in parameter order. */
	public static function sourceFunctionExpr(facts:HxSourceFunction, body:TypedExpr, defaults:Array<TypedExpr>, type:TyType, position:Null<HxPos>,
			?bindings:Array<TyLocalBinding>):TypedExpr
		return new TypedExpr(SourceFunction, type, position, facts.getBindingNames(), [body].concat(defaults), null, false, 0, 0.0, null, null, null, null,
			null, bindings, null, null, null, facts.getSignature(), facts);

	/** Coverage comes from exact name/type resolution before pattern locals enter scope. */
	public static function switchExpr(scrutinee:TypedExpr, patterns:Array<HxSwitchPattern>, branches:Array<TypedExpr>, type:TyType, position:Null<HxPos>,
			?bindings:Array<TyLocalBinding>, exhaustive:Bool = false):TypedExpr
		return new TypedExpr(SwitchExpr, type, position, null, [scrutinee].concat(branches == null ? [] : branches), patterns, exhaustive, 0, 0.0, null, null,
			null, null, null, bindings);

	/** Retain the original selected constructor beside the applied nominal result; null denotes unresolved or implicit construction. */
	public static function newValue(typePath:String, arguments:Array<TypedExpr>, type:TyType, position:Null<HxPos>,
			?constructor:TypedConstructorApplication):TypedExpr
		return new TypedExpr(NewValue, type, position, [typePath], arguments, null, false, 0, 0.0, null, null, null, null, null, null, null, null, null, null,
			null, null, null, constructor);

	/** Execute the selected parent body on the current receiver; this call does not allocate a value. */
	public static function superConstructorCall(receiver:TypedExpr, arguments:Array<TypedExpr>, position:Null<HxPos>,
			?constructor:TypedConstructorApplication):TypedExpr {
		if (receiver == null || receiver.getTag() != SuperValue)
			throw "parent construction requires the typed super receiver";
		return new TypedExpr(Call, TyType.fromHintText("Void"), position, null, [receiver].concat(arguments), null, false, 0, 0.0, null, null, null, null,
			null, null, null, null, null, null, null, null, null, constructor);
	}

	public static function unary(op:HxUnaryOperator, fixity:HxUnaryFixity, expression:TypedExpr, type:TyType, position:Null<HxPos>):TypedExpr
		return new TypedExpr(Unary, type, position, null, [expression], null, false, 0, 0.0, null, op, fixity);

	public static function binary(op:String, left:TypedExpr, right:TypedExpr, type:TyType, position:Null<HxPos>):TypedExpr
		return new TypedExpr(Binary, type, position, [op], [left, right]);

	public static function assign(target:TypedExpr, value:TypedExpr, type:TyType, position:Null<HxPos>):TypedExpr
		return new TypedExpr(Assign, type, position, null, [target, value]);

	public static function compoundAssign(op:String, target:TypedExpr, value:TypedExpr, type:TyType, position:Null<HxPos>):TypedExpr
		return new TypedExpr(CompoundAssign, type, position, [op], [target, value]);

	public static function ternary(condition:TypedExpr, whenTrue:TypedExpr, whenFalse:TypedExpr, type:TyType, position:Null<HxPos>):TypedExpr
		return new TypedExpr(Ternary, type, position, null, [condition, whenTrue, whenFalse]);

	public static function anonymous(fieldNames:Array<String>, fieldValues:Array<TypedExpr>, type:TyType, position:Null<HxPos>):TypedExpr
		return new TypedExpr(Anonymous, type, position, fieldNames, fieldValues);

	public static function arrayComprehension(name:String, iterable:TypedExpr, guard:Null<TypedExpr>, value:TypedExpr, type:TyType, position:Null<HxPos>,
			?binding:TyLocalBinding):TypedExpr {
		final children = [iterable];
		if (guard != null)
			children.push(guard);
		children.push(value);
		return new TypedExpr(ArrayComprehension, type, position, [name], children, null, guard != null, 0, 0.0, null, null, null, null, null,
			binding == null ? [] : [binding]);
	}

	public static function arrayDecl(values:Array<TypedExpr>, type:TyType, position:Null<HxPos>):TypedExpr
		return new TypedExpr(ArrayDecl, type, position, null, values);

	/** Executable collection mutation after typing; its operands retain normal source evaluation order. */
	public static function arrayAppend(array:TypedExpr, value:TypedExpr, position:Null<HxPos>):TypedExpr
		return new TypedExpr(ArrayAppend, TyType.fromHintText("Void"), position, null, [array, value]);

	/** Ordered insertion retains exact key and value occurrences after source typing. */
	public static function mapInsert(map:TypedExpr, key:TypedExpr, value:TypedExpr, position:Null<HxPos>):TypedExpr
		return new TypedExpr(MapInsert, TyType.fromHintText("Void"), position, null, [map, key, value]);

	public static function arrayAccess(array:TypedExpr, index:TypedExpr, type:TyType, position:Null<HxPos>):TypedExpr
		return new TypedExpr(ArrayAccess, type, position, null, [array, index]);

	public static function range(start:TypedExpr, end:TypedExpr, type:TyType, position:Null<HxPos>):TypedExpr
		return new TypedExpr(Range, type, position, null, [start, end]);

	/** Derived iteration bounds read snapshots declared before the loop; later passes must preserve them. */
	public static function fixedRange(start:TypedExpr, end:TypedExpr, type:TyType, position:Null<HxPos>):TypedExpr
		return new TypedExpr(FixedRange, type, position, null, [start, end]);

	/** Selected switch arms remain lexical regions; pattern bindings retain their typed identities. */
	public static function controlSwitch(scrutinee:TypedExpr, patterns:Array<HxSwitchPattern>, branches:Array<TypedExpr>, type:TyType, position:Null<HxPos>,
			bindings:Array<TyLocalBinding>, exhaustive:Bool = false):TypedExpr
		return new TypedExpr(ControlSwitch, type, position, null, [scrutinee].concat(branches), patterns, exhaustive, 0, 0.0, null, null, null, null, null,
			bindings);

	/** Shared typing certifies unchanged storage for selected abstract or class-literal conversions; authored casts use false. */
	public static function castValue(expression:TypedExpr, typeHint:String, type:TyType, position:Null<HxPos>, preservesRepresentation:Bool = false):TypedExpr
		return new TypedExpr(Cast, type, position, [typeHint], [expression], null, preservesRepresentation);

	public function isRepresentationPreservingCast():Bool
		return tag == Cast && boolValue;

	public static function untypedValue(expression:TypedExpr, type:TyType, position:Null<HxPos>):TypedExpr
		return new TypedExpr(Untyped, type, position, null, [expression]);

	public static function opaque(kind:TypedOpaqueExprKind, raw:String, type:TyType, position:Null<HxPos>):TypedExpr
		return new TypedExpr(Opaque, type, position, [raw], null, null, false, 0, 0.0, null, null, null, kind);

	/** Ordered expression sequence used by shared semantic lowering. **/
	public static function block(expressions:Array<TypedExpr>, type:TyType, position:Null<HxPos>):TypedExpr
		return new TypedExpr(Block, type, position, null, expressions);

	/** Compiler-owned temporary declaration; its source type hint remains representation input. **/
	public static function temporary(name:String, typeHint:String, initializer:TypedExpr, type:TyType, position:Null<HxPos>, ?binding:TyLocalBinding):TypedExpr
		return new TypedExpr(Temporary, type, position, [name, typeHint == null ? "" : typeHint], [initializer], null, false, 0, 0.0, null, null, null, null,
			null, binding == null ? [] : [binding]);

	public function getTag():TypedExprTag
		return tag;

	public function getType():TyType
		return type;

	public function getPosition():Null<HxPos>
		return position;

	public function getTexts():Array<String>
		return texts.copy();

	public function getExpressions():Array<TypedExpr>
		return expressions.copy();

	public function getPatterns():Array<HxSwitchPattern>
		return patterns.copy();

	/** A recorded proof permits result storage without an artificial default branch. */
	public function getSwitchHasExhaustiveCoverage():Bool {
		if (tag != SwitchExpr && tag != ControlSwitch)
			throw "switch coverage requires a typed switch expression";
		return boolValue;
	}

	public function getBoolValue():Bool
		return boolValue;

	/** Whether a bare imported field/call must be projected through its exact owner. **/
	public function getRequiresOwnerQualification():Bool
		return boolValue;

	/** Exact type named by the winning `using` directive for an extension call. **/
	public function getExtensionProvider():Null<TyNominalTypeId>
		return tag == Call ? extensionProvider : null;

	/** Whether a `VariableDeclaration` was written with `final`. **/
	public function getVariableIsFinal():Bool
		return boolValue;

	/** Whether a `VariableDeclaration` was written with `static`. **/
	public function getVariableIsStatic():Bool
		return intValue != 0;

	public function getIntValue():Int
		return intValue;

	public function getFloatValue():Float
		return floatValue;

	public function getDeclaration():Null<TyDeclarationInfo>
		return constructorApplication == null ? declaration : constructorApplication.getDeclaration();

	public function getConstructorApplication():Null<TypedConstructorApplication>
		return constructorApplication;

	public function getUnaryOperator():Null<HxUnaryOperator>
		return unaryOperator;

	public function getUnaryFixity():Null<HxUnaryFixity>
		return unaryFixity;

	public function getOpaqueKind():Null<TypedOpaqueExprKind>
		return opaqueKind;

	/** Exact declaration selected for a bare or receiver-qualified field read, when the current typed subset can resolve it. **/
	public function getFieldInfo():Null<TyFieldInfo>
		return fieldInfo;

	/** Local declaration facts owned by this declaration, read, lambda, loop, or compiler temporary. **/
	public function getLocalBindings():Array<TyLocalBinding>
		return localBindings.copy();

	/** Implicit runtime uses owned by an exact catch-handler lambda. */
	public function getCatchUses():Array<TypedCatchUse>
		return catchUses.copy();

	/** Written annotations remain separate from this node's selected semantic type. */
	public function getLambdaSignature():Null<HxLambdaSignature>
		return lambdaSignature;

	/** Authored function kind, placement, and default indexes survive selected-type changes. */
	public function getSourceFunction():Null<HxSourceFunction>
		return sourceFunction;

	/** Exact source destination selected before any helper function can alter control flow. */
	public function getControlTarget():Null<TyControlTarget>
		return controlTarget;

	/** Attach a resolved destination while preserving source syntax and all other typed facts. */
	public function withControlTarget(target:TyControlTarget):TypedExpr
		return new TypedExpr(tag, type, position, texts, expressions, patterns, boolValue, intValue, floatValue, declaration, unaryOperator, unaryFixity,
			opaqueKind, fieldInfo, localBindings, extensionProvider, runtimeTypeTarget, catchUses, lambdaSignature, sourceFunction, target, sourceCatches,
			constructorApplication, argumentBinding, namedArguments);

	public function withCatchUses(uses:Array<TypedCatchUse>):TypedExpr
		return new TypedExpr(tag, type, position, texts, expressions, patterns, boolValue, intValue, floatValue, declaration, unaryOperator, unaryFixity,
			opaqueKind, fieldInfo, localBindings, extensionProvider, runtimeTypeTarget, uses, lambdaSignature, sourceFunction, controlTarget, sourceCatches,
			constructorApplication, argumentBinding, namedArguments);

	/** Preserve semantic facts on copies; changing the input type invalidates switch coverage and representation-preserving casts. **/
	public function withExpressions(children:Array<TypedExpr>):TypedExpr {
		final sameInputType = children.length > 0
			&& expressions.length > 0
			&& children[0].getType().getSemanticKey() == expressions[0].getType().getSemanticKey();
		final retainedFact = switch tag {
			case SwitchExpr | ControlSwitch: boolValue && sameInputType;
			case Cast: boolValue && sameInputType && children.length == 1 && expressions.length == 1;
			case _: boolValue;
		};
		return new TypedExpr(tag, type, position, texts, children, patterns, retainedFact, intValue, floatValue, declaration, unaryOperator, unaryFixity,
			opaqueKind, fieldInfo, localBindings, extensionProvider, runtimeTypeTarget, catchUses, lambdaSignature, sourceFunction, controlTarget,
			sourceCatches, constructorApplication, argumentBinding, namedArguments);
	}

	/** Instantiate an inline expression and its retained call proof atomically; local declarations are remapped by the inline owner. */
	@:allow(TypedRequiredInlineLowering)
	function withInlineTypes(children:Array<TypedExpr>, bindings:haxe.ds.StringMap<TyType>):TypedExpr {
		assertArgumentBinding();
		if (!bindings.iterator().hasNext())
			return withExpressions(children);
		if (localBindings.length != 0 || constructorApplication != null || catchUses.length != 0 || controlTarget != null || lambdaSignature != null
			|| sourceFunction != null)
			throw "inline type specialization requires explicit support for owned locals, construction, or nested control";
		final applied = TyTypeSubstitution.apply(type, bindings);
		// An unchecked authored cast has no written target. Giving it a type hint
		// would change its runtime checking behavior during source projection.
		final appliedTexts = tag == Cast && texts.length == 1 && texts[0].length > 0 ? [applied.getCanonicalDisplay()] : texts;
		return new TypedExpr(tag, applied, position, appliedTexts, children, patterns, boolValue, intValue, floatValue, declaration, unaryOperator,
			unaryFixity, opaqueKind, fieldInfo, [], extensionProvider, runtimeTypeTarget, [], null, null, null, sourceCatches, null,
			argumentBinding == null ? null : argumentBinding.substituteTypes(bindings),
			namedArguments == null ? null : namedArguments.substituteTypes(bindings));
	}

	/** Re-label one structurally identical expression for a shared semantic view such as abstract `this`. **/
	public function withType(semanticType:TyType):TypedExpr
		return new TypedExpr(tag, semanticType, position, texts, expressions, patterns,
			tag != Cast ? boolValue : boolValue
			&& semanticType.getSemanticKey() == type.getSemanticKey(), intValue, floatValue, declaration, unaryOperator,
			unaryFixity, opaqueKind, fieldInfo, localBindings, extensionProvider, runtimeTypeTarget, catchUses, lambdaSignature, sourceFunction,
			controlTarget, sourceCatches, constructorApplication, argumentBinding, namedArguments);
}
