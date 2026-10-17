#if macro
import haxe.macro.Context;
import haxe.macro.Type;
import haxe.macro.TypedExprTools;
import reflaxe.helpers.ClassFieldHelper;
import reflaxe.lifecycle.ProgramRevision;
import reflaxe.ocaml.OcamlCompiler;
import reflaxe.ocaml.OcamlTargetDefinition;
import reflaxe.ocaml.lowered.OcamlCallPlan.OcamlCallPlanner;

/**
	Checks producer ownership through the real declaration and function planners.

	Private access supplies a complete typed-module inventory without emitting
	files. It does not manufacture the producer proof that these tests inspect.
**/
@:access(reflaxe.ocaml.OcamlCompiler)
class EnumFunctionProducerFixture {
	static final REVISION = "enum-function-producer-fixture";

	static function owner(name:String):ClassType {
		return switch (Context.getType(name)) {
			case TInst(reference, _): reference.get();
			case _: throw "expected an enum producer fixture class: " + name;
		};
	}

	static function compilerFor(classes:Array<ClassType>):OcamlCompiler {
		final target = OcamlTargetDefinition.create();
		final compiler = target.compiler;
		compiler.setOptions(target.options);
		compiler.pendingStaticStorageModuleOrder = classes.map(type -> type.module);
		compiler.pendingStaticStorageClassesByModule = [];
		for (type in classes)
			compiler.pendingStaticStorageClassesByModule.set(type.module, [type]);
		compiler.beginProgramRevision(new ProgramRevision(REVISION, classes.length, classes.length));
		return compiler;
	}

	/** A write anywhere in the function tree invalidates the initializer's producer proof. */
	public static function checkMutation():Void {
		final type = owner("EnumFunctionProducerCases");
		for (name in ["unchanged", "reassigned", "capturedWrite"]) {
			final compiler = compilerFor([type]);
			final field = type.statics.get().filter(field -> field.name == name)[0];
			final data = ClassFieldHelper.findFuncData(field, type, true);
			if (data == null || data.expr == null)
				throw "missing producer fixture body: " + name;
			data.bindProgramRevision(REVISION);
			var call:Null<TypedExpr> = null;
			function visit(expression:TypedExpr):Void {
				switch (expression.expr) {
					case TCall({expr: TLocal(local)}, _) if (local.name == "producer"):
						call = expression;
					case _:
				}
				TypedExprTools.iter(expression, visit);
			}
			visit(data.expr);
			if (call == null)
				throw "missing producer fixture call: " + name;
			compiler.sealFunctionPlans(data);
			final plan = compiler.functionPlanRegistry.functionSyntaxInputFor(data).plan;
			final admitted = plan.calls.decisionFor(call) != null;
			if (admitted != (name == "unchanged"))
				throw "enum function producer proof ignored local mutation: " + name;
		}
		Sys.println("ENUM_FUNCTION_PRODUCER_MUTATION:PASS");
	}

	/** An unrelated enum producer must not authorize an unchecked result. */
	public static function checkDeclarationOrder():Void {
		final consumer = owner("EnumUnprovenProducer");
		final producer = owner("PreliminaryCallFactsEnumProducer");
		final field = consumer.statics.get().filter(field -> field.name == "unproven")[0];
		final provenField = producer.statics.get().filter(field -> field.name == "select")[0];
		for (classes in [[consumer, producer], [producer, consumer]]) {
			final compiler = compilerFor(classes);
			if (!compiler.functionPlanRegistry.hasCallableDeclaration(OcamlCallPlanner.calleeId(producer, provenField)))
				throw "proven enum result lost its callable declaration: " + classes[0].name;
			if (compiler.functionPlanRegistry.hasCallableDeclaration(OcamlCallPlanner.calleeId(consumer, field)))
				throw "unproven enum result gained a callable declaration: " + classes[0].name;
		}
		Sys.println("ENUM_FUNCTION_DECLARATION_ORDER:PASS");
	}
}
#end
