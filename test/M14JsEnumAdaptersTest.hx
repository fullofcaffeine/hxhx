import backend.js.JsClassInheritancePlan;
import backend.js.JsTargetCore;
import backend.js.JsWriter;

/** Existing test-framework adapters must consume declared enums rather than a second synthetic layout. */
class M14JsEnumAdaptersTest {
	static function main():Void {
		// Deliberately reorder constructors: the adapter cannot own their indexes.
		final source = "package utest; enum Assertation { Warning(msg:String); Success(pos:Int); Ignore(reason:String); Error(e:String, stack:Array<String>); } "
			+ "enum Other { Warning(msg:String); } class Main { static function main():Void {} }";
		final resolved = new ResolvedModule("utest.Assertation", "utest/Assertation.hx", ParserStage.parse(source, "utest/Assertation.hx"));
		final typed = TyperStage.typeResolvedModule(resolved, TyperIndex.build([resolved]));
		final plan = new JsClassInheritancePlan(new MacroExpandedProgram([typed], false));
		final assertion = plan.requireRuntimeEnum("utest.Assertation");
		final other = plan.requireRuntimeEnum("utest.Assertation.Other");
		final writer = new JsWriter();
		writer.writeln("var $hxEnums = Object.create(null);");
		for (owner in [assertion, other])
			backend.js.JsEnumDeclaration.emit(writer, {constructors: owner.enumConstructors, reference: owner.reference, runtimeName: owner.fullName});
		backend.js.JsEnumRuntime.emit(writer);
		writer.writeln("function execute() {");
		@:privateAccess JsTargetCore.emitUtestTestHandlerExecuteBody(writer, assertion);
		writer.writeln("}");
		writer.writeln("function add(value) {");
		@:privateAccess JsTargetCore.emitUtestFixtureResultAddBody(writer, "value");
		writer.writeln("}");
		writer.writeln("function same(left,right) { var status={recursive:true,path:''};");
		@:privateAccess JsTargetCore.emitUtestAssertSameAsBody(writer, "left", "right", "status", "null");
		writer.writeln("}");
		writer.writeln("function enumName(value) {");
		@:privateAccess JsTargetCore.emitUtestReportToolsEnumName(writer);
		writer.writeln("return __hx_enumName(value); }");
		writer.writeln("function typeName(value) {");
		@:privateAccess JsTargetCore.emitUtestAssertGetTypeNameBody(writer, "value");
		writer.writeln("}");
		writer.writeln("function run(fixture) { var handler={fixture:fixture,results:[]}; execute.call(handler); return handler.results[0]; }");
		writer.writeln("var ignored=run({ignoringInfo:{isIgnored:true,ignoreReason:'reason'}});");
		writer.writeln("var warning=run({});");
		writer.writeln("var error=run({target:{fail:function(){throw 'boom';}},method:'fail'});");
		writer.writeln("if(ignored._hx_index!==2 || ignored.reason!=='reason' || $hx_enum_name(ignored)!=='Ignore') throw Error('ignored representation');");
		writer.writeln("if(warning._hx_index!==0 || warning.msg!=='no assertions' || $hx_enum_name(warning)!=='Warning') throw Error('warning representation');");
		writer.writeln("if(error._hx_index!==3 || error.e!=='boom' || !Array.isArray(error.stack) || error.stack.length!==0) throw Error('error representation');");
		writer.writeln("var totals={warnings:0,ignores:0,errors:0}; var result={stats:{addWarnings:function(n){totals.warnings+=n;},addIgnores:function(n){totals.ignores+=n;},addErrors:function(n){totals.errors+=n;}}};");
		writer.writeln("add.call(result,warning); add.call(result,ignored); add.call(result,error);");
		writer.writeln("if(totals.warnings!==1 || totals.ignores!==1 || totals.errors!==1 || result.list.length!==3) throw Error('enum aggregation');");
		writer.writeln("var equal=" + backend.js.JsEnumDeclaration.construct(assertion, "Warning", ["'no assertions'"]) + ";");
		writer.writeln("var unequal=" + backend.js.JsEnumDeclaration.construct(assertion, "Warning", ["'different'"]) + ";");
		writer.writeln("var foreign=" + backend.js.JsEnumDeclaration.construct(other, "Warning", ["'no assertions'"]) + ";");
		writer.writeln("if(!same(warning,equal) || same(warning,unequal) || same(warning,foreign)) throw Error('enum equality');");
		writer.writeln("if(enumName(warning)!=='Warning' || typeName(warning)!=='utest.Assertation') throw Error('enum display');");
		writer.writeln("if(enumName('Warning')!==null || enumName({__hx_ctor:'Warning',__hx_index:0,__hx_params:[]})!==null) throw Error('retired enum layout');");
		writer.writeln("console.log('JS_ENUM_ADAPTERS_RUNTIME:PASS');");
		final output = JsRuntimeFixture.reserveOutput();
		final script = output + "/adapters.js";
		sys.io.File.saveContent(script, writer.toString());
		if (@:privateAccess M14NekoTypedProgramProjectionIntegrationTest.run("node", [script]) != "JS_ENUM_ADAPTERS_RUNTIME:PASS\n")
			throw "enum adapter output differs: " + output;
		Sys.println("JS_ENUM_ADAPTERS:PASS " + output);
	}
}
