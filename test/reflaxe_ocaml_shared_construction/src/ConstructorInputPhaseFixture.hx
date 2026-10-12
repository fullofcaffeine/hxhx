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
			Sys.println("CONSTRUCTOR_INPUT_PHASE:PASS classes=5");
		});
	}

	/** Each source constructor starts with a body effect or super call, never this field assignment. */
	static function check(types:Array<Type>, afterGeneration:Bool):Void {
		// Independent Haxe 4.3.7 eval, JavaScript and Neko runs establish the
		// order below. Three fields keep alphabetical sorting from passing by chance.
		final expected = [
			"Item" => ["value"],
			"Parent" => ["base"],
			"Child" => ["values"],
			"OrderedFields" => ["middle", "alpha", "zeta"],
			"ImplicitChild" => ["middle", "alpha", "zeta"]
		];
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
					final initializers = expected.get(owner.name);
					for (index in 0...initializers.length) {
						final matchesInitializer = statements.length > index && switch (statements[index].expr) {
							case TBinop(OpAssign, {expr: TField({expr: TConst(TThis)}, FInstance(declaring, _, field))}, _): declaring.get()
									.module == owner.module && declaring.get().name == owner.name && field.get().name == initializers[index];
							case _: false;
						};
						if (matchesInitializer != afterGeneration)
							throw "constructor initializer phase/order changed for " + owner.name + "." + initializers[index];
					}
					var bodyIndex = afterGeneration ? initializers.length : 0;
					if (owner.name == "ImplicitChild") {
						final parameter = switch (body.expr) {
							case TFunction({args: [{v: variable}]}): variable;
							case _: throw "omitted constructor lost the inherited parameter";
						};
						final forwardsParameter = statements.length == bodyIndex + 1 && switch (statements[bodyIndex].expr) {
							case TCall({expr: TConst(TSuper)}, [{expr: TLocal(argument)}]): argument.id == parameter.id;
							case _: false;
						};
						if (!forwardsParameter)
							throw "omitted constructor lost its ordered super call or argument identity";
						checked++;
						continue;
					}
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
					final expectedLabel = switch (owner.name) {
						case "Item": "body";
						case "Parent": "base-body";
						case "Child": "child-body";
						case "OrderedFields": "ordered-body";
						case _: throw "unexpected constructor phase owner";
					};
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
		if (checked != 5)
			throw "constructor phase fixture requires all five source classes";
	}
}
