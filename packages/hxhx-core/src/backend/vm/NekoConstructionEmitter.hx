package backend.vm;

import backend.vm.NekoEmitContext;
import backend.vm.NekoEmitContext.NekoClassInfo;

/**
	Constructs a class instance or returns an abstract's initialized backing value.

	Class selection belongs to NekoClassConstructionPlan. Shared prototypes hold
	methods and uninitialized field defaults; each new instance links to its class
	prototype before its initializers run. Methods save their receiver for nested
	closures. Explicit field initializers create instance-owned values in source order.
	The shared emitter retains ordinary expression and statement rendering.
**/
@:access(backend.vm.NekoTargetCore)
class NekoConstructionEmitter {
	public static function render(out:Array<String>, context:NekoEmitContext, info:NekoClassInfo):Void {
		final plan = NekoTargetCore.constructionPlan(context, info);
		if (plan.returnsBackingValue) {
			renderAbstract(out, context, info, plan);
			return;
		}
		renderBody(out, context, info);
		out.push(context.typedProgram.runtimeHelperName("__hxhx_runtime_type_definition")
			+ "("
			+ NekoTargetCore.quote(NekoRuntimeTypeRegistry.classDescriptorIdentity(context.typedProgram, info.cls))
			+ ")."
			+ context.typedProgram.runtimeHelperName("__hxhx_constructor")
			+ " = "
			+ NekoTargetCore.renderDeclaredConstructorRef(context, info.fullName)
			+ ";");
	}

	/**
		A private initialization cell lets an early constructor return finish normally
		without returning from the factory. Only the final backing value escapes as
		the constructed result. No abstract descriptor or instance methods are added.
		Captured constructor expressions retain the same cell through ordinary scope
		capture; a constructor throw propagates before the factory can return a value.
	 */
	static function renderAbstract(out:Array<String>, context:NekoEmitContext, info:NekoClassInfo, plan:NekoClassConstructionPlan):Void {
		final ctor = plan.effectiveConstructor();
		if (ctor == null)
			throw "Neko abstract construction requires its declared constructor";
		final args = [for (arg in HxFunctionDecl.getArgs(ctor)) NekoTargetCore.safeIdent(arg.name)];
		final useVarArgs = NekoTargetCore.shouldUseVarArgs(context, args, ctor);
		final selfName = context.typedProgram.constructionReceiverName();
		out.push(NekoTargetCore.renderConstructorDefinitionPrefix(context, info.fullName) + NekoTargetCore.renderFunctionStart(args, useVarArgs));
		if (useVarArgs) {
			final arrayName = NekoFunctionParameters.arrayName(args);
			for (index in 0...args.length)
				out.push("  var " + args[index] + " = " + arrayName + "[" + index + "];");
		}
		out.push("  var " + selfName + " = $new(null);");
		out.push("  " + selfName + ".__hx_value = null;");
		out.push("  " + NekoTargetCore.renderInitializerRef(context, info) + "(" + [selfName].concat(args).join(", ") + ");");
		out.push("  return " + selfName + ".__hx_value;");
		out.push(NekoTargetCore.renderFunctionEnd(useVarArgs));
		out.push("");
		renderClassInitializer(out, context, info, plan, ctor);
	}

	/** Retain the original descriptor on instances even if source later replaces the class binding. */
	static function renderBody(out:Array<String>, context:NekoEmitContext, info:NekoClassInfo):Void {
		if (NekoTargetCore.isListTypePath(info.fullName)) {
			out.push(NekoTargetCore.renderConstructorDefinitionPrefix(context, info.fullName) + "function() {");
			out.push("  return __hxhx_list_new();");
			out.push("}");
			out.push("");
			return;
		}
		if (NekoTargetCore.isSysIoProcessTypePath(info.fullName)) {
			NekoTargetCore.renderProcessConstructorFactory(out, context, info);
			return;
		}
		final plan = NekoTargetCore.constructionPlan(context, info);
		final ctor = plan.effectiveConstructor();
		final args = new Array<String>();
		if (ctor != null) {
			for (arg in HxFunctionDecl.getArgs(ctor))
				args.push(NekoTargetCore.safeIdent(arg.name));
		}
		if (NekoTargetCore.needsTestLocalStaticBasicSlot(info))
			out.push("var " + NekoTargetCore.testLocalStaticBasicSlotName() + " = null;");
		final selfName = context.typedProgram.constructionReceiverName();
		final prototype = context.typedProgram.runtimeHelperName("__hxhx_runtime_type_definition")
			+ "("
			+ NekoTargetCore.quote(NekoRuntimeTypeRegistry.classDescriptorIdentity(context.typedProgram, info.cls))
			+ ").prototype";
		if (plan.lineage.length > 1) {
			final parent = context.typedProgram.runtimeHelperName("__hxhx_runtime_type_definition")
				+ "("
				+ NekoTargetCore.quote(NekoRuntimeTypeRegistry.classDescriptorIdentity(context.typedProgram, plan.lineage[1].getDeclaration()))
				+ ").prototype";
			out.push("$objsetproto(" + prototype + ", " + parent + ");");
		}
		for (field in HxClassDecl.getFields(info.cls))
			if (!HxFieldDecl.getIsStatic(field))
				out.push(prototype + "." + NekoTargetCore.safeIdent(HxFieldDecl.getName(field)) + " = null;");
		for (method in plan.methods)
			if (method.owner == plan.lineage[0])
				NekoTargetCore.renderPrototypeMethod(out, NekoTargetCore.withSelf(context, selfName, info), prototype, selfName, method.body.getDeclaration());
		if (plan.hasOwnStringConversion())
			out.push(prototype + ".__string = function() { return this.toString(); };");
		final useVarArgs = NekoTargetCore.shouldUseVarArgs(context, args, ctor);
		out.push(NekoTargetCore.renderConstructorDefinitionPrefix(context, info.fullName) + NekoTargetCore.renderFunctionStart(args, useVarArgs));
		if (useVarArgs) {
			final arrayName = NekoFunctionParameters.arrayName(args);
			for (index in 0...args.length)
				out.push("  var " + args[index] + " = " + arrayName + "[" + index + "];");
		}
		out.push("  var " + selfName + " = $new(null);");
		out.push("  $objsetproto(" + selfName + ", " + prototype + ");");
		final typeSlot = context.typedProgram.runtimeHelperName("__hxhx_runtime_type");
		out.push("  "
			+ selfName
			+ "."
			+ typeSlot
			+ " = "
			+ context.typedProgram.runtimeHelperName("__hxhx_runtime_type_definition")
			+ "("
			+ NekoTargetCore.quote(NekoRuntimeTypeRegistry.classDescriptorIdentity(context.typedProgram, info.cls))
			+ ");");
		out.push("  " + selfName + ".__hx_ctor = " + NekoTargetCore.quote(info.fullName) + ";");
		out.push("  " + selfName + ".__hx_params = $array(" + args.join(", ") + ");");
		out.push("  " + selfName + ".__hx_value = " + (args.length > 0 ? args[0] : "null") + ";");
		out.push("  " + NekoTargetCore.renderInitializerRef(context, info) + "(" + [selfName].concat(args).join(", ") + ");");
		out.push("  return " + selfName + ";");
		out.push(NekoTargetCore.renderFunctionEnd(useVarArgs));
		out.push("");
		renderClassInitializer(out, context, info, plan, ctor);
	}

	/** Runs one class's initialization on the receiver allocated by the most-derived factory. */
	static function renderClassInitializer(out:Array<String>, context:NekoEmitContext, info:NekoClassInfo, plan:NekoClassConstructionPlan,
			ctor:Null<HxFunctionDecl>):Void {
		final selfName = context.typedProgram.constructionReceiverName();
		final args = ctor == null ? [] : [for (arg in HxFunctionDecl.getArgs(ctor)) NekoTargetCore.safeIdent(arg.name)];
		final allArgs = [selfName].concat(args);
		final instanceContext = NekoTargetCore.withSelf(context, selfName, info);
		final initializerContext = ctor == null ? instanceContext : NekoTargetCore.withFunctionArgs(instanceContext, ctor);
		final useVarArgs = NekoTargetCore.shouldUseVarArgs(context, allArgs, ctor);
		out.push(NekoTargetCore.renderInitializerRef(context, info) + " = " + NekoTargetCore.renderFunctionStart(allArgs, useVarArgs));
		if (useVarArgs) {
			final arrayName = NekoFunctionParameters.arrayName(allArgs);
			out.push("  var " + selfName + " = " + arrayName + "[0];");
			if (ctor != null)
				NekoTargetCore.renderVarArgBindings(out, initializerContext, HxFunctionDecl.getArgs(ctor), "  ", arrayName, 1);
		}
		if (ctor != null)
			NekoTargetCore.renderCaptureParameters(out, initializerContext, [for (arg in HxFunctionDecl.getArgs(ctor)) arg.name], "  ");
		for (field in HxClassDecl.getFields(info.cls)) {
			final init = HxFieldDecl.getInit(field);
			if (!HxFieldDecl.getIsStatic(field) && init != null) {
				final fieldContext = NekoTargetCore.withFieldInitializer(instanceContext, field);
				final selected = context.typedProgram.requireDeclaredInitializer(field);
				selected.requireExpression(init);
				final body = NekoControlStatements.initializerBody(init, selected.getStableIdentity(), fieldContext);
				for (statement in body.statements)
					NekoTargetCore.renderStmt(out, fieldContext, statement, "  ");
				if (body.value != null)
					out.push("  " + selfName + "." + NekoTargetCore.safeIdent(HxFieldDecl.getName(field)) + " = "
						+ NekoTargetCore.renderExpr(fieldContext, body.value) + ";");
			}
		}
		final declared = NekoTargetCore.findFunction(info.cls, "new", false);
		if (declared != null && !NekoTargetCore.isMacroFunction(declared)) {
			for (stmt in HxFunctionDecl.getBody(declared))
				NekoTargetCore.renderStmt(out, initializerContext, stmt, "  ");
		} else if (plan.lineage.length > 1) {
			final parent = NekoTargetCore.exactClassInfo(context, plan.lineage[1]);
			out.push("  " + NekoTargetCore.renderInitializerRef(context, parent) + "(" + allArgs.join(", ") + ");");
		}
		out.push(NekoTargetCore.renderFunctionEnd(useVarArgs));
		out.push("");
	}
}
