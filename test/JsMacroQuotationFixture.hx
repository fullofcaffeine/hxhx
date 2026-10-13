import backend.js.JsClassInheritancePlan;
import backend.js.JsEmitScope;

/** One checked program supplies both quotation references and matching runtime factories. */
typedef JsMacroQuotationFixture = {
	final scope:JsEmitScope;
	final declarations:JsClassInheritancePlan;
};

/** Supply real macro enum declarations to isolated JavaScript quotation checks. */
function scope():JsEmitScope
	return load().scope;

/** Load once when a native observer also needs to emit those declarations. */
function load():JsMacroQuotationFixture {
	final program = JsSourceProgramFixture.build({
		sources: [
			{path: "Main.hx", source: "class Main {static function main():Void {final quoted = macro null;}}"}
		],
		requiredModules: ["haxe.macro.Expr"]
	});
	final declarations = new JsClassInheritancePlan(program);
	final scope:JsEmitScope = {
		resolveLocal: _ -> null,
		resolveClassRef: _ -> null,
		resolveSuperClassRef: () -> null,
		enumDeclarations: declarations.requireRuntimeEnum
	};
	return {scope: scope, declarations: declarations};
}
