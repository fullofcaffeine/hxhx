#if macro
import haxe.macro.Context;
import haxe.macro.Type;
import haxe.macro.TypeTools;

/** Runs unchanged against stock Haxe and the macro-host override's compile-time API. */
class MacroHostTypeParameterFixture {
	public static function run():Void {
		final marker:Type = TDynamic(null);
		final first = classParameters("ParameterCases.First");
		final second = classParameters("ParameterCases.Second");
		requireMarker(TypeTools.applyTypeParameters(first[0].t, first, [marker]), "owned class parameter");
		switch TypeTools.applyTypeParameters(second[0].t, first, [marker]) {
			case TInst(reference, []):
				switch reference.get().kind {
					case KTypeParameter(_):
					case _: throw "An unrelated parameter lost its type-parameter identity";
				}
			case _:
				throw "Equal names must not substitute a different owner's parameter";
		}
		switch Context.getType("Null") {
			case TAbstract(reference, _):
				final owner = reference.get();
				requireMarker(TypeTools.applyTypeParameters(owner.params[0].t, owner.params, [marker]), "Null parameter");
			case _:
				throw "Expected the standard Null abstract";
		}
		switch Context.getType("ParameterCases.Box") {
			case TType(reference, _):
				final owner = reference.get();
				switch TypeTools.applyTypeParameters(owner.type, owner.params, [marker]) {
					case TAnonymous(fields): requireMarker(fields.get().fields[0].type, "record field");
					case _: throw "Expected a substituted record";
				}
			case _:
				throw "Expected the generic Box alias";
		}
		requireMarker(TypeTools.applyTypeParameters(marker, [], []), "empty substitution");
		var rejected = false;
		try {
			TypeTools.applyTypeParameters(first[0].t, first, []);
		} catch (_:haxe.Exception) {
			rejected = true;
		}
		if (!rejected)
			throw "Mismatched parameter counts must fail";
		Sys.println("MACRO_HOST_TYPE_PARAMETERS:PASS");
	}

	static function classParameters(path:String):Array<TypeParameter> {
		return switch Context.getType(path) {
			case TInst(reference, _): reference.get().params;
			case _: throw "Expected a generic class";
		};
	}

	static function requireMarker(type:Type, label:String):Void {
		switch type {
			case TDynamic(null):
			case _:
				throw label + " did not receive the substitution marker";
		}
	}
}
#end
