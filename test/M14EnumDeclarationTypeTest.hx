/** The indexed enum declaration must describe values and payload results without target erasure. */
class M14EnumDeclarationTypeTest {
	static function main():Void {
		final source = 'enum Choice<T> { Empty; Item(value:T); }
enum Plain { First; Pair(number:Int, text:String); }
class Ordinary {
 public static var First:String = "field";
 public static function Item(value:Int):String return "method";
}
class Main {}';
		final resolved = new ResolvedModule("Main", "Main.hx", ParserStage.parse(source, "Main.hx"));
		final index = TyperIndex.build([resolved]);
		for (entry in [
			{
				name: "Plain",
				field: "First",
				method: "Pair",
				generic: false
			},
			{
				name: "Choice",
				field: "Empty",
				method: "Item",
				generic: true
			}
		]) {
			final owner = index.getByFullName("Main." + entry.name);
			if (owner == null || !owner.getIsEnum())
				throw "enum lost its nominal declaration";
			final value = owner.fieldType(entry.field);
			final constructor = owner.staticMethod(entry.method);
			if (constructor == null || !owner.declarationForSignature(constructor).getIsEnumConstructor())
				throw "payload constructor lost its declaration role";
			for (type in [value, constructor.getReturnType()]) {
				if (type == null || type.getNominalIdentity() != owner.getIdentity())
					throw "enum result lost its exact owner: " + entry.name + ": " + (type == null ? "missing" : type.getSemanticKey());
				final arguments = type.getTypeArguments();
				if (arguments.length != (entry.generic ? 1 : 0))
					throw "enum result lost its declared type arguments: " + entry.name;
				if (entry.generic
					&& (!arguments[0].isTypeParameter() || arguments[0].getSemanticKey() != constructor.getArgs()[0].getSemanticKey()))
					throw "enum payload and result do not share the same generic binder";
			}
		}
		final ordinary = index.getByFullName("Main.Ordinary");
		if (ordinary.getIsEnum()
			|| ordinary.fieldType("First").getSemanticKey() != "primitive:String"
			|| ordinary.staticMethod("Item").getReturnType().getSemanticKey() != "primitive:String"
			|| ordinary.declarationForSignature(ordinary.staticMethod("Item")).getIsEnumConstructor())
			throw "same-named ordinary members acquired enum semantics";
		Sys.println("ENUM_DECLARATION_TYPE:PASS");
	}
}
