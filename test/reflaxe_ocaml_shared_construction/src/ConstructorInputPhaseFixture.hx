import haxe.macro.Context;
import haxe.macro.Type;

/**
	Checks the stock constructor input at the phase where Reflaxe consumes it.

	Haxe adds instance field assignments after onGenerate. A constructor captured
	earlier omits those effects, while adding them again after generation repeats
	them. The shared target must account for this difference between host inputs.
**/
class ConstructorInputPhaseFixture {
	/** Register observers without rewriting either the source fields or constructor bodies. */
	public static function install():Void {
		var captured:Array<Type> = [];
		// Retain the supplied class handles intentionally: the post-generation
		// callback observes Haxe's final bodies, as Reflaxe's capture lifecycle does.
		Context.onGenerate(types -> {
			captured = types.copy();
			check(captured, false);
		}, false);
		Context.onAfterGenerate(() -> {
			check(captured, true);
			Sys.println("CONSTRUCTOR_INPUT_PHASE:PASS classes=3");
		});
	}

	/** Each source constructor starts with a body effect or super call, never this field assignment. */
	static function check(types:Array<Type>, afterGeneration:Bool):Void {
		final expected = ["Item" => "value", "Parent" => "base", "Child" => "values"];
		var checked = 0;
		for (type in types)
			switch (type) {
				case TInst(reference, _):
					final owner = reference.get();
					if (owner.module != "Main" || !expected.exists(owner.name))
						continue;
					if (owner.constructor == null)
						throw "constructor phase fixture lost " + owner.name;
					final body = owner.constructor.get().expr();
					final statements = switch (body == null ? null : body.expr) {
						case TFunction({expr: {expr: TBlock(items)}}): items;
						case _: throw "constructor phase fixture requires a complete block: " + owner.name;
					};
					if (statements.length == 0)
						throw "constructor phase fixture lost source effects: " + owner.name;
					final startsWithInitializer = switch (statements[0].expr) {
						case TBinop(OpAssign, {expr: TField({expr: TConst(TThis)}, FInstance(declaring, _, field))}, _): declaring.get()
								.module == owner.module && declaring.get().name == owner.name && field.get().name == expected.get(owner.name);
						case _: false;
					};
					if (startsWithInitializer != afterGeneration)
						throw "constructor field-initializer phase changed for " + owner.name + ": afterGeneration=" + afterGeneration;
					var bodyIndex = afterGeneration ? 1 : 0;
					if (owner.name == "Child") {
						final superIndex = afterGeneration ? 1 : 0;
						final callsSuper = statements.length > superIndex && switch (statements[superIndex].expr) {
							case TCall({expr: TConst(TSuper)}, []): true;
							case _: false;
						};
						if (!callsSuper)
							throw "constructor phase changed field-initializer order relative to super";
						bodyIndex++;
					}
					final expectedLabel = owner.name == "Item" ? "body" : owner.name == "Parent" ? "base-body" : "child-body";
					final retainsBody = statements.length > bodyIndex && switch (statements[bodyIndex].expr) {
						case TCall({expr: TField(_, FInstance(_, _, method))}, [{expr: TConst(TString(label))}]): method.get()
								.name == "push" && label == expectedLabel;
						case _: false;
					};
					if (!retainsBody)
						throw "constructor phase lost or moved the authored body effect for " + owner.name;
					checked++;
				case _:
			}
		if (checked != 3)
			throw "constructor phase fixture requires all three source classes";
	}
}
