/** Written record types must retain their fields and resolve nested declaration identities. */
class M14AnonymousHintTypingTest {
	static function check(condition:Bool, message:String):Void {
		if (!condition)
			throw message;
	}

	static function field(type:TyType, name:String):TyType {
		final index = type.getAnonymousFieldNames().indexOf(name);
		check(index >= 0, "missing structural field " + name + " in " + type.getSemanticKey());
		return type.getAnonymousFieldTypes()[index];
	}

	static function main():Void {
		final simple = TyType.fromHintText("{value:Int, label:String}");
		check(simple.getSemanticKey() == "anonymous:{label:primitive:String,value:primitive:Int}", "written record lost its structure");
		final nested = TyType.fromHintText("{item:Null<{name:String, count:Int}>, callback:(Int,String)->Bool}");
		check(field(field(nested, "item").getNullableInner(), "count").getSemanticKey() == "primitive:Int", "nested record was split at its comma");
		check(field(nested, "callback").getFunctionArguments().length == 2, "callable field lost its arguments");
		final generic = TyType.fromHintText("Box<{value:Int, callback:Int->String}, Bool>");
		check(generic.getTypeArguments().length == 2
			&& generic.getTypeArguments()[0].isAnonymous(), "generic record argument lost its boundary");
		final callbacks = TyType.fromHintText("Box<Int->String, Int->Bool>");
		check(!callbacks.isFunction() && callbacks.getTypeArguments().length == 2 && callbacks.getTypeArguments()[1].isFunction(),
			"function arrows closed a generic argument list");
		check(TyType.fromHintText("{}").isAnonymous(), "empty record lost its type");
		for (hint in [
			"{?value:Int}",
			"{var value:Int;}",
			"{>Base, value:Int}",
			"{value:Int, value:String}"
		])
			check(TyType.fromHintText(hint).isUnresolved(), "unsupported record form became a required-field contract: " + hint);

		final source = "package sample; class Model {} class Holder<T> { public var value:{model:Model, item:T}; public function echo(input:{model:Model,item:T}):{model:Model,item:T} { var local:{model:Model,item:T} = input; return local; } }";
		final resolved = new ResolvedModule("sample.Model", "Model.hx", ParserStage.parse(source, "Model.hx"));
		final index = TyperIndex.build([resolved]);
		final holder = index.getByFullName("sample.Model.Holder");
		check(holder != null, "missing secondary declaration");
		final declared = holder.getFieldInfos()[0].getType();
		check(field(declared, "model").getNominalIdentity().getCanonicalName() == "sample.Model", "record field did not resolve the nominal declaration");
		check(field(declared, "item").isTypeParameter(), "record field did not resolve the generic binder");
		final typed = TyperStage.typeResolvedModule(resolved, index);
		final local = typed.getTypedClasses()[1].getFunctions()[0].getBody().getStatements()[0];
		check(local.getLocalBindings()[0].getType().getSemanticKey() == declared.getSemanticKey(), "local annotation differs from the declaration index");
		check(local.getExpressions()[0].getType().getSemanticKey() == declared.getSemanticKey(), "argument annotation differs from the declaration index");
		Sys.println("ANONYMOUS_HINT_TYPING:PASS");
	}
}
