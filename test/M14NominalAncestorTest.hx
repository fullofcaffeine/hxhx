/** Applied inheritance must preserve binder order and reject incomplete graph evidence. */
class M14NominalAncestorTest {
	static function main():Void {
		final source = "interface View<A,B> {}\n"
			+ "class Base<X,Y> implements View<Y,X> {"
			+ " public function get(value:X):Y { return null; }"
			+ " public function shadow<X>(value:X):X { return value; }"
			+ " public function bounded<T:{item:X}>(value:T):T { return value; } }\n"
			+ "class Child<P,Q> extends Base<Q,P> {}\n"
			+ "class Other {}\n"
			+ "class CycleA extends CycleB {}\nclass CycleB extends CycleA {}\n"
			+ "class Left implements View<String,Int> {}\n"
			+ "class Conflict extends Left implements View<Int,String> {}\n"
			+ "class Missing extends Absent {}\n";
		final resolved = new ResolvedModule("Ancestors", "Ancestors.hx", ParserStage.parse(source, "Ancestors.hx"));
		final index = TyperIndex.build([resolved]);
		function type(name:String, arguments:Array<TyType>):TyType {
			return TyType.nominal(index.getByFullName("Ancestors." + name).getIdentity(), arguments);
		}
		final stringType = TyType.fromHintText("String");
		final intType = TyType.fromHintText("Int");
		final target = index.getByFullName("Ancestors.View").getIdentity();
		final result = TyNominalAncestor.view(index, type("Child", [stringType, intType]), target);
		if (result == null || result.getSemanticKey() != type("View", [stringType, intType]).getSemanticKey())
			throw "ancestor traversal lost reordered binder substitutions";
		final receiver = type("Child", [stringType, intType]);
		final base = index.getByFullName("Ancestors.Base");
		final declared = base.instanceMethod("get");
		final applied = TyNominalApplication.signature(index, base, receiver, declared);
		if (applied.getArgs()[0].getSemanticKey() != "primitive:Int" || applied.getReturnType().getSemanticKey() != "primitive:String")
			throw "inherited member signature lost receiver arguments";
		if (!declared.getArgs()[0].isTypeParameter() || !declared.getReturnType().isTypeParameter())
			throw "receiver application mutated the declaration signature";
		final shadow = base.instanceMethod("shadow");
		final shadowApplied = TyNominalApplication.signature(index, base, receiver, shadow);
		if (shadowApplied.getArgs()[0].getSemanticKey() != shadow.getArgs()[0].getSemanticKey()
			|| shadowApplied.getReturnType().getSemanticKey() != shadow.getReturnType().getSemanticKey())
			throw "receiver application replaced a same-named method binder";
		final bounded = base.declarationForSignature(base.instanceMethod("bounded"));
		final bound = bounded.getResolvedTypeParameterConstraints().get(bounded.getTypeParameterIds()[0].getCanonicalKey())[0];
		final appliedBound = TyNominalApplication.applyType(index, base, receiver, bound);
		if (appliedBound.getAnonymousFieldTypes()[0].getSemanticKey() != "primitive:Int"
			|| !bound.getAnonymousFieldTypes()[0].isTypeParameter())
			throw "inherited bound and signature disagree about receiver arguments";
		for (name in ["Other", "CycleA", "Conflict", "Missing", "Child"])
			if (TyNominalAncestor.view(index, type(name, []), target) != null)
				throw "invalid ancestor graph supplied type evidence: " + name;
		Sys.println("NOMINAL_ANCESTOR_CONTRACT:PASS");
	}
}
