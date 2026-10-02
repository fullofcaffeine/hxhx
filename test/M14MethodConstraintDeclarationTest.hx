/** Generic bounds retain declaration scope and binder identity before call inference begins. */
class M14MethodConstraintDeclarationTest {
	static function module(name:String, source:String):ResolvedModule {
		final path = name.split(".").join("/") + ".hx";
		return new ResolvedModule(name, path, ParserStage.parse(source, path));
	}

	static function require(condition:Bool, message:String):Void {
		if (!condition)
			throw message;
	}

	static function main():Void {
		for (hint in ["{?item:Int}", "{var item:Int;}", "{item:Int,item:String}", "{>Base,item:Int}"])
			require(TyType.fromHintText(hint).isUnresolved(), "unsupported record contract was silently simplified: " + hint);
		final nested = TyType.fromHintText("{callback:(Int,String)->Bool, child:{value:Int}}");
		require(nested.isAnonymous() && nested.getAnonymousFieldTypes().length == 2, "nested record delimiters were split");
		require(nested.getAnonymousFieldTypes()[0].getFunctionArguments().length == 2, "callback arguments were split as fields");
		final appliedRecord = TyType.fromHintText("Pair<{left:Int,right:String}>");
		require(appliedRecord.getTypeArguments().length == 1, "record fields were split as generic arguments");
		require(appliedRecord.getTypeArguments()[0].getAnonymousFieldNames().join(",") == "left,right", "generic record fields were lost");
		final appliedCallback = TyType.fromHintText("Pair<(Int,String)->Bool>");
		require(appliedCallback.getTypeArguments().length == 1 && appliedCallback.getTypeArguments()[0].getFunctionArguments().length == 2,
			"callback inputs were split as generic arguments");
		final index = TyperIndex.build([
			module("foreign.Bound", "package foreign; class Bound {}"),
			module("caller.Bound", "package caller; class Bound {}"),
			module("owner.Owner",
				"package owner; import foreign.Bound; class Owner<T> {"
				+ " public function compound<U:Bound & Marker>(value:U):U { return value; }"
				+ " public function applied<U:Pair<T>>(value:U):U { return value; }"
				+ " public function shadow<T:Pair<T>>(value:T):T { return value; }"
				+ " public function structural<U:{item:T}>(value:U):U { return value; }"
				+ "} interface Marker {} class Pair<V> {}")
		]);
		final owner = index.getByFullName("owner.Owner");
		require(owner != null, "constraint owner was not indexed");
		function declaration(name:String):TyDeclarationInfo {
			final result = owner.declarationForSignature(owner.instanceMethod(name));
			require(result != null, "missing declaration " + name);
			return result;
		}
		function bounds(name:String):Array<TyType> {
			final selected = declaration(name);
			final key = selected.getTypeParameterIds()[0].getCanonicalKey();
			final result = selected.getResolvedTypeParameterConstraints().get(key);
			require(result != null, "missing resolved bounds " + name);
			return result;
		}
		final compound = bounds("compound");
		require(compound.length == 2, "compound bounds must remain separate");
		require(compound[0].getNominalIdentity().getCanonicalName() == "foreign.Bound", "bound lost its declaring import");
		require(compound[1].getNominalIdentity().getCanonicalName() == "owner.Owner.Marker", "same-module bound lost its owner");
		final applied = bounds("applied")[0];
		require(applied.getNominalIdentity().getCanonicalName() == "owner.Owner.Pair", "applied bound lost its nominal identity");
		final classParameter = applied.getTypeArguments()[0].getTypeParameterIdentity();
		require(classParameter != null, "class parameter was erased from the bound");
		final shadow = declaration("shadow");
		final methodParameter = shadow.getTypeParameterIds()[0];
		require(bounds("shadow")[0].getTypeArguments()[0].getTypeParameterIdentity().equals(methodParameter), "method binder did not shadow class binder");
		require(!classParameter.equals(methodParameter), "class and method binders were conflated");
		final structural = bounds("structural")[0];
		require(structural.isAnonymous(), "structural bound was not retained");
		require(structural.getAnonymousFieldTypes()[0].getTypeParameterIdentity().equals(classParameter), "structural field lost its class binder");
		compound.resize(0);
		require(bounds("compound").length == 2, "caller mutated declaration-owned bound list");
		final selected = declaration("compound");
		selected.getResolvedTypeParameterConstraints().remove(selected.getTypeParameterIds()[0].getCanonicalKey());
		require(bounds("compound").length == 2, "caller mutated declaration-owned bound map");
		Sys.println("METHOD_CONSTRAINT_DECLARATION:PASS");
	}
}
