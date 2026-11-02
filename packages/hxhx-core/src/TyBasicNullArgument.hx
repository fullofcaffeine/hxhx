/**
	Upstream per-target rule for `null` passed to a required basic-type parameter,
	such as `f(null)` for `static function f(v:Int)`.

	Why: Haxe 4.3.7 accepts the call on its dynamic targets (JavaScript, Neko,
	Python, Lua, PHP and the interpreter) and rejects it on its static targets (C++,
	HashLink, Java, C#, Flash) with "On static platforms, null can't be used as basic
	type Int". The rule covers static and instance methods, constructors and function
	values alike. An optional `?v:Int` parameter accepts null on every target.

	What: a "basic" parameter is a known, required type that
	`TyNullArgument.acceptsLiteral` rejects: `Int`, `Float`, `Bool` and abstracts over
	them. `admit` lets declared-method selection score such a null as
	`Null<parameter>`, so the declared parameter and the generated call stay as
	written; `check` applies only the static-target rejection on paths that already
	accept the null. The native OCaml target is not static here, as upstream's
	custom targets are not; its backend raises the catchable Null Access at the call
	boundary because an unboxed parameter cannot hold null. Indexed setters follow a
	different upstream rule (`TyIndexedNullValue`).
**/
final STATIC_TARGETS = ["cpp", "hl", "java", "cs", "flash"];

/** True for targets where upstream reports "null can't be used as basic type". */
function isStaticTarget(ctx:TyperContext):Bool {
	for (target in STATIC_TARGETS)
		if (ctx.hasDefine(target))
			return true;
	return false;
}

/** True when `parameter` is required and cannot ordinarily hold a null literal. */
function requiresValue(parameter:Null<TyType>, optional:Bool, index:TyperIndex):Bool {
	return parameter != null
		&& !optional
		&& !parameter.hasUnknownComponent()
		&& !parameter.isNullable()
		&& !TyNullArgument.acceptsLiteral(parameter, index);
}

function staticPlatformError(parameter:TyType, ctx:TyperContext, pos:HxPos):TyperError
	return new TyperError(ctx.getFilePath(), pos, "On static platforms, null can't be used as basic type " + parameter.getDisplay());

/**
	Prepare one declared candidate's argument types. A null literal at a basic
	parameter is scored as `Null<parameter>` on dynamic targets and rejected with the
	upstream diagnostic on static targets. `types` is updated in place; arguments
	past the fixed parameters (rest values) are left alone.
**/
function admit(signature:TyFunSig, types:Array<TyType>, ctx:TyperContext, pos:HxPos):Void {
	for (index in basicNullPositions(signature, types, ctx.getIndex())) {
		if (isStaticTarget(ctx))
			throw staticPlatformError(signature.getArgs()[index], ctx, pos);
		types[index] = TyType.nullable(signature.getArgs()[index]);
	}
}

/**
	A copy of `types` for scoring one candidate, with each null literal at a basic
	parameter scored as `Null<parameter>`. Typing has already rejected such calls on
	static targets, so this copy only lets later selection (such as the constructor
	application the backend consumes) agree with the accepted call.
**/
function scoringTypes(signature:TyFunSig, types:Array<TyType>, ctx:TyperContext):Array<TyType> {
	final positions = isStaticTarget(ctx) ? [] : basicNullPositions(signature, types, ctx.getIndex());
	if (positions.length == 0)
		return types;
	final scored = types.copy();
	for (index in positions)
		scored[index] = TyType.nullable(signature.getArgs()[index]);
	return scored;
}

/** Fixed-parameter positions where a null literal meets a basic parameter. */
private function basicNullPositions(signature:TyFunSig, types:Array<TyType>, index:TyperIndex):Array<Int> {
	final parameters = signature.getArgs();
	final optional = signature.getArgOptional();
	final rest = signature.getArgRest();
	final positions = [];
	for (position in 0...types.length) {
		if (position >= parameters.length || (position < rest.length && rest[position]))
			break;
		if (types[position].isNullLiteral()
			&& requiresValue(parameters[position], position < optional.length && optional[position], index))
			positions.push(position);
	}
	return positions;
}

/** Reject a null literal at a basic parameter on static targets; paths that already accept it call this. */
function check(parameters:Array<Null<TyType>>, optional:Array<Bool>, types:Array<TyType>, ctx:TyperContext, pos:HxPos):Void {
	if (!isStaticTarget(ctx))
		return;
	for (index in 0...types.length)
		if (index < parameters.length
			&& types[index].isNullLiteral()
			&& requiresValue(parameters[index], index < optional.length && optional[index], ctx.getIndex()))
			throw staticPlatformError(parameters[index], ctx, pos);
}
