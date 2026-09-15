package backend.vm;

import backend.vm.NekoEmitContext;
import backend.vm.NekoEmitContext.NekoClassInfo;

/**
	Allocates one object and runs inherited initialization on that receiver.

	Class selection belongs to NekoClassConstructionPlan. This renderer installs
	the selected method closures before invoking class initializers in source
	order. The shared emitter retains ordinary expression and statement rendering.
**/
@:access(backend.vm.NekoTargetCore)
class NekoConstructionEmitter {
	public static function render(out:Array<String>, context:NekoEmitContext, info:NekoClassInfo):Void {
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
		final useVarArgs = NekoTargetCore.shouldUseVarArgs(context, args, ctor);
		out.push(NekoTargetCore.renderConstructorDefinitionPrefix(context, info.fullName) + NekoTargetCore.renderFunctionStart(args, useVarArgs));
		if (useVarArgs) {
			final arrayName = NekoFunctionParameters.arrayName(args);
			for (index in 0...args.length)
				out.push("  var " + args[index] + " = " + arrayName + "[" + index + "];");
		}
		out.push("  var " + selfName + " = $new(null);");
		out.push("  " + selfName + ".__hx_ctor = " + NekoTargetCore.quote(info.fullName) + ";");
		out.push("  " + selfName + ".__hx_params = $array(" + args.join(", ") + ");");
		out.push("  " + selfName + ".__hx_value = " + (args.length > 0 ? args[0] : "null") + ";");
		for (owner in plan.lineage)
			for (field in HxClassDecl.getFields(owner.getDeclaration()))
				if (!HxFieldDecl.getIsStatic(field))
					out.push("  " + selfName + "." + NekoTargetCore.safeIdent(HxFieldDecl.getName(field)) + " = null;");
		for (method in plan.methods) {
			final owner = NekoTargetCore.exactClassInfo(context, method.owner);
			NekoTargetCore.renderInstanceMethod(out, NekoTargetCore.withSelf(context, selfName, owner), selfName, method.body.getDeclaration());
		}
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
		for (field in HxClassDecl.getFields(info.cls)) {
			final init = HxFieldDecl.getInit(field);
			if (!HxFieldDecl.getIsStatic(field) && init != null)
				out.push("  " + selfName + "." + NekoTargetCore.safeIdent(HxFieldDecl.getName(field)) + " = "
					+ NekoTargetCore.renderExpr(instanceContext, init) + ";");
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
