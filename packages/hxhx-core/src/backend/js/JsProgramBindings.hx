package backend.js;

/** Compiler-owned host bindings requested by the completed feature-selection pass. */
typedef JsProgramBindingPlan = {
	final needsGlobal:Bool;
	final needsUid:Bool;
}

/** Select only declared runtime hooks; retained but unused provider methods do not activate them. */
function select(program:MacroExpandedProgram):JsProgramBindingPlan {
	final features = program.getSelectedRuntimeFeatures();
	final uid = features.indexOf("$global.$haxeUID") >= 0;
	return {needsGlobal: uid || features.indexOf("js.Lib.global") >= 0, needsUid: uid};
}

/** Host order is the public js.Lib.global contract, including the top-level this fallback. */
function hostExpression():String {
	return 'typeof window != "undefined" ? window : typeof global != "undefined" ? global : typeof self != "undefined" ? self : this';
}

/** Open the ordinary wrapper or declare the same host binding in classic output. */
function open(writer:JsWriter, plan:JsProgramBindingPlan, classic:Bool):Void {
	if (classic) {
		if (plan.needsGlobal)
			writer.writeln("var $global = " + hostExpression() + ";");
	} else {
		writer.writeln(plan.needsGlobal ? "(function ($global) {" : "(function () {");
		writer.pushIndent();
		writer.writeln('"use strict";');
	}
	// A second generated program shares the existing counter instead of restarting IDs.
	if (plan.needsUid)
		writer.writeln("$global.$haxeUID |= 0;");
}

/** Evaluate host selection outside the strict wrapper, where fallback this is the host object. */
function close(writer:JsWriter, plan:JsProgramBindingPlan, classic:Bool):Void {
	if (!classic) {
		writer.popIndent();
		writer.writeln(plan.needsGlobal ? "})(" + hostExpression() + ");" : "})();");
	}
}
