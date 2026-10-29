/** Default integer formatting must not replace an abstract's authored text behavior. */
class M14TypedStringOperandTest {
	public static function run():Void {
		final source = 'class Main { static function main():Void {} }
abstract Plain(Int) from Int to Int {}
abstract Named(Int) from Int to Int { public function toString():String { return "named"; } }
abstract Converted(Int) from Int to Int { @:to public function text():String { return "converted"; } }
abstract Opaque(Int) {}
abstract Generic<T>(T) from T to T {}';
		final resolved = new ResolvedModule("Main", "Main.hx", ParserStage.parse(source, "Main.hx"));
		final index = TyperIndex.build([resolved]);
		function operand(name:String, ?arguments:Array<TyType>):TypedExpr {
			final owner = index.getAbstractByFullName("Main." + name);
			if (owner == null)
				throw "missing abstract conversion test declaration";
			return TypedExpr.nameRead("value", TyType.nominal(owner.getIdentity(), arguments == null ? [] : arguments), null);
		}
		for (value in [operand("Plain"), operand("Generic", [TyType.fromHintText("Int")])]) {
			final converted = TypedStringOperand.lower(value, index);
			if (converted.getType().getSemanticKey() != "primitive:Int"
				|| !converted.isRepresentationPreservingCast()
				|| converted.getExpressions().length != 1
				|| converted.getExpressions()[0] != value)
				throw "declared integer text view lost its operand or exact storage proof";
		}
		for (value in [
			operand("Named"),
			operand("Converted"),
			operand("Opaque"),
			operand("Generic", [TyType.fromHintText("String")]),
			TypedExpr.nameRead("plain", TyType.fromHintText("Int"), null),
			TypedExpr.nameRead("floatValue", TyType.fromHintText("Float"), null)
		])
			if (TypedStringOperand.lower(value, index) != value)
				throw "default integer formatting replaced an unselected conversion";
		Sys.println("TYPED_STRING_OPERAND:PASS");
	}
}
