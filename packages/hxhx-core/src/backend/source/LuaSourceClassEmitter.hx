package backend.source;

import backend.GenIrProgram;
import HxExpr;
import backend.source.SourceFunctionRenderFrame.SourceFunctionRenderFrameTools;
import backend.source.LuaClassPlan.LuaClassOwner;
import backend.source.LuaClassPlan.LuaFieldDefault;

private enum LuaExecutable {
	Function(projection:TypedBackendFunctionProjection);
	Initializer(projection:TypedBackendFieldInitializerProjection);
}

/**
	Emit ordinary Lua classes from the exact declarations selected by typing.
	All tables exist before methods and initializers run. Instance methods retain
	the receiver through runtime-bound closures; inheritance follows semantic
	class identities, including secondary types and colliding short names.
**/
@:access(backend.source.SourceTargetCommon)
@:access(backend.source.LuaStringLocalCallLowering)
class LuaSourceClassEmitter {
	final program:GenIrProgram;
	final plan:LuaClassPlan;
	final classes:Array<LuaClassOwner>;
	final externs:LuaExternValues;

	public function new(program:GenIrProgram) {
		this.program = program;
		plan = new LuaClassPlan(program);
		classes = plan.copyClasses();
		externs = new LuaExternValues(program);
	}

	function requireOwner(identity:String):LuaClassOwner
		return plan.requireOwner(identity);

	/** Publish declarations before executable initialization so forward references remain valid. */
	public function render(main:TypedBackendClassProjection):Array<String> {
		final out = new Array<String>();
		final reachable = new LuaStaticMethodReachability(classes, main);
		SourceTargetCommon.appendSourceNativeTemplateLines(out, "", "lua/runtime", "Classes.lua");
		out.push("local " + plan.tableName + " = {}");
		out.push("local "
			+ plan.runtimeName
			+ " = {initialize = __hxhx_lua_initialize, isInstance = __hxhx_lua_is_instance, valueType = type, protect = pcall, raise = error}");
		for (owner in classes) {
			out.push(owner.reference + " = __hxhx_lua_class()");
			final namespace = owner.packagePath.length == 0 ? "" : SourceTargetCommon.appendLuaNamespace(out, owner.packagePath) + ".";
			out.push(namespace + SourceTargetCommon.sanitizeTypeName(owner.declaredName) + " = " + owner.reference);
		}
		for (owner in classes) {
			final parent = owner.parentIdentity;
			if (parent != null)
				out.push("__hxhx_lua_parent(" + owner.reference + ", " + requireOwner(parent).reference + ")");
			for (projection in owner.projection.getFunctions())
				if (reachable.includes(projection))
					renderFunction(out, owner, projection);
			renderDefaults(out, owner);
		}
		for (owner in classes)
			for (initializer in owner.projection.getFieldInitializers())
				if (initializer.getField().getIsStatic())
					renderInitializer(out, owner, initializer, owner.reference + "." + name(initializer.getField().getName()), "");
		out.push("local function main() " + plan.requireProjection(main).reference + ".main() end");
		return out;
	}

	function ownerExpression(owner:LuaClassOwner):HxExpr
		return EField(EIdent(plan.tableName), owner.reference.split(".")[1]);

	static function name(value:String):String
		return SourceTargetCommon.valueName(Lua, value);

	function renderFunction(out:Array<String>, owner:LuaClassOwner, projection:TypedBackendFunctionProjection):Void {
		final declaration = projection.getDeclaration();
		final method = HxFunctionDecl.getName(declaration);
		if (HxFunctionDecl.getMetadata(declaration).indexOf("macro") >= 0 || owner.isInterface)
			return;
		final isStatic = HxFunctionDecl.getIsStatic(declaration);
		final parameters = [
			for (argument in HxFunctionDecl.getArgs(declaration))
				name(HxFunctionArg.getName(argument))
		];
		if (!isStatic)
			parameters.unshift(plan.receiverName);
		final prefix = method == "new" ? "__hxhx_lua_constructor(" + owner.reference + ", " : isStatic ? owner.reference
			+ "."
			+ name(method)
			+ " = " : "__hxhx_lua_method("
			+ owner.reference
			+ ", "
			+ SourceTargetCommon.quoteString(method)
			+ ", ";
		out.push(prefix + "function(" + parameters.join(", ") + ")");
		final frame = SourceFunctionRenderFrameTools.forTypedFunction(Lua, projection, program, plan);
		final arrays = new LuaArrayIndexLowering();
		TypedBackendSourceWalk.functionDeclaration(declaration, expression -> arrays.add(projection.findArrayAccess(expression)), _ -> {});
		for (value in projection.getDefaults()) {
			final parameter = name(HxFunctionArg.getName(HxFunctionDecl.getArgs(declaration)[value.slot]));
			final expression = SourceFunctionBodyRewriter.expressionWithOriginal(value.expression,
				(original, rebuilt) -> lower(owner, Function(projection), arrays, original, rebuilt));
			out.push("  if "
				+ parameter
				+ " == nil then "
				+ parameter
				+ " = "
				+ SourceTargetCommon.renderExprWithFrame(frame, expression)
				+ " end");
		}
		final body = SourceFunctionBodyRewriter.bodyWithOriginal(projection.getBody(),
			(original, rebuilt) -> lower(owner, Function(projection), arrays, original, rebuilt));
		for (line in SourceTargetCommon.renderFunctionStmtsWithFrame(frame, body, "  ", projection.getStableIdentity()))
			out.push(line);
		out.push(isStatic ? "end" : "end)");
	}

	static function defaultLiteral(value:LuaFieldDefault):String
		return switch value {
			case Zero: "0";
			case False: "false";
			case Nil: "nil";
		};

	function renderDefaults(out:Array<String>, owner:LuaClassOwner):Void {
		out.push("__hxhx_lua_field_defaults(" + owner.reference + ", function(" + plan.receiverName + ")");
		for (field in owner.fields)
			if (!field.isStatic)
				out.push("  " + plan.receiverName + "." + name(field.name) + " = " + defaultLiteral(field.initial));
		out.push("end)");
		out.push("__hxhx_lua_field_initializers(" + owner.reference + ", function(" + plan.receiverName + ")");
		for (initializer in owner.projection.getFieldInitializers())
			if (!initializer.getField().getIsStatic())
				renderInitializer(out, owner, initializer, plan.receiverName + "." + name(initializer.getField().getName()), "  ");
		out.push("end)");
		for (field in owner.fields)
			if (field.isStatic)
				out.push(owner.reference + "." + name(field.name) + " = " + defaultLiteral(field.initial));
	}

	function renderInitializer(out:Array<String>, owner:LuaClassOwner, projection:TypedBackendFieldInitializerProjection, destination:String,
			indent:String):Void {
		projection.requireCaptureCatalog().assertCurrent();
		final arrays = new LuaArrayIndexLowering();
		TypedBackendSourceWalk.expression(projection.getExpression(), expression -> arrays.add(projection.findArrayAccess(expression)));
		final expression = SourceFunctionBodyRewriter.expressionWithOriginal(projection.getExpression(),
			(original, rebuilt) -> lower(owner, Initializer(projection), arrays, original, rebuilt));
		final body = TypedControlStatements.initializerBody(expression, projection.getStableIdentity());
		// Lowering above consumes this initializer's exact catalogs before syntax rendering.
		// Statement regions retain their field identity instead of borrowing a method owner.
		if (body.statements.length != 0)
			throw "Lua field initializer requires statement-region rendering: " + projection.getStableIdentity();
		if (body.value != null)
			out.push(indent + destination + " = " + SourceTargetCommon.renderExpr(Lua, body.value));
	}

	function lower(owner:LuaClassOwner, executable:LuaExecutable, arrays:LuaArrayIndexLowering, original:HxExpr, rebuilt:HxExpr):HxExpr {
		if (TypedRuntimeTypeSource.isMarker(original))
			return switch executable {
				case Function(projection): externs.functionValue(projection, original);
				case Initializer(projection): externs.initializerValue(projection, original);
			};
		final callable = switch executable {
			case Function(projection): projection.findCallableExpression(original);
			case Initializer(projection): projection.findCallableExpression(original);
		};
		if (callable != null && (callable.getTag() == FieldRead || callable.getTag() == NameRead)) {
			final declaration = callable.getDeclaration();
			if (declaration != null && declaration.getIsStatic()) {
				final external = externs.methodValue(declaration.getOwner().getCanonicalName(), declaration.getIdentity().getCanonicalKey());
				if (external != null)
					return external;
			}
		}
		final locals = switch executable {
			case Function(value): value.getLocalCatalog();
			case Initializer(value): value.getLocalCatalog();
		};
		final fields = switch executable {
			case Function(value): value.getFieldReadCatalog();
			case Initializer(value): value.getFieldReadCatalog();
		};
		// String decisions use the original typed transport, before field qualification.
		switch [original, rebuilt] {
			case [
				ECall(EField(receiver, field), arguments),
				ECall(EField(nextReceiver, _), nextArguments)
			]:
				final helper = LuaStringLocalCallLowering.stringHelper(field, arguments.length);
				if (helper != null && LuaStringLocalCallLowering.dependsOnExactStringValue(receiver, locals, fields))
					return ECall(EIdent(helper), [nextReceiver].concat(nextArguments));
			case [EBinop("+", left, right), EBinop("+", nextLeft, nextRight)]:
				if (LuaStringLocalCallLowering.dependsOnExactStringValue(left, locals, fields)
					|| LuaStringLocalCallLowering.dependsOnExactStringValue(right, locals, fields))
					return ECall(EIdent("__hxhx_lua_string_concat"), [nextLeft, nextRight]);
			case _:
		}
		switch rebuilt {
			case EThis:
				return EIdent(plan.receiverName);
			case EField(receiver, _):
				final access = switch executable {
					case Function(projection): projection.findField(original);
					case Initializer(projection): projection.findField(original);
				};
				if (access != null && access.getField().getIsStatic()) {
					final field = access.getField();
					final selected = plan.findOwner(field.getOwner().getCanonicalName());
					if (selected != null) {
						final value = EField(ownerExpression(selected), field.getName());
						return access.getReceiver().match(ValueReceiver) ? EDiscardThen(receiver, value) : value;
					}
				}
			case EIdent(value):
				final field = locals.findByProjectedName(value) == null ? fields.findByProjectedName(value) : null;
				if (field != null) {
					final fact = field.getField();
					return EField(fact.getIsStatic() ? ownerExpression(requireOwner(fact.getOwner().getCanonicalName())) : EIdent(plan.receiverName),
						fact.getName());
				}
				if (locals.findByProjectedName(value) == null) {
					final callable = switch executable {
						case Function(projection): projection.findCallableExpression(original);
						case Initializer(projection): projection.findCallableExpression(original);
					};
					final declaration = callable == null ? null : callable.getDeclaration();
					if (declaration != null && (plan.findOwner(declaration.getOwner().getCanonicalName()) != null))
						return EField(declaration.getIsStatic() ? ownerExpression(requireOwner(declaration.getOwner()
							.getCanonicalName())) : EIdent(plan.receiverName),
							declaration.getSignature().getName());
				}
			case ENew(_, arguments) | ECall(ESuper, arguments):
				final selected = switch executable {
					case Function(value): value.requireConstructor(original);
					case Initializer(value): value.requireConstructor(original);
				};
				final identity = selected.getConstructedType().getNominalIdentity();
				// Core and runtime constructors retain their existing intrinsic renderer.
				// Only classes admitted by this plan use its table-allocation protocol.
				if (identity == null && !selected.getIsSuperCall())
					return rebuilt;
				if (identity == null)
					throw "Lua parent constructor requires an exact nominal owner";
				final target = plan.findOwner(identity.getCanonicalName());
				if (target == null && !selected.getIsSuperCall())
					return rebuilt;
				if (target == null)
					throw "Lua parent constructor has no emitted owner: " + identity.getCanonicalName();
				return selected.getIsSuperCall() ? ECall(EField(EIdent(plan.runtimeName), "initialize"),
					[ownerExpression(target), EIdent(plan.receiverName)].concat(arguments)) : ECall(EField(ownerExpression(target), "new"), arguments);
			case _:
		}
		final instance = TypedExactCallSource.decodeInstance(rebuilt);
		if (instance != null) {
			final selected = switch executable {
				case Function(value): value.findInstanceCall(original);
				case Initializer(value): value.findInstanceCall(original);
			};
			if (selected == null)
				throw "Lua instance call lost its typed owner";
			return ECall(EField(instance.receiver, instance.method), instance.arguments);
		}
		final staticCall = TypedExactStaticCallSource.decode(rebuilt);
		if (staticCall != null) {
			final external = externs.staticCall(staticCall);
			if (external != null)
				return external;
		}
		if (staticCall != null && (plan.findOwner(staticCall.owner) != null))
			return ECall(EField(ownerExpression(requireOwner(staticCall.owner)), staticCall.method), staticCall.arguments);
		return arrays.expression(original, rebuilt);
	}
}
