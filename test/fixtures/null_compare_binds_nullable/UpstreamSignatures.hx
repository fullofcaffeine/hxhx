import haxe.macro.Context;

/** Print stock Haxe's full signature of each static function, `Null` wrappers and result included. */
class UpstreamSignatures {
	public static function check(className:String):Void {
		Context.onAfterTyping(_ -> {
			final observations:Array<String> = [];
			switch Context.getType(className) {
				case TInst(reference, _):
					for (field in reference.get().statics.get())
						observations.push(field.name + "=" + haxe.macro.TypeTools.toString(field.type));
				case _:
					throw "fixture requires the class " + className;
			}
			observations.sort((left, right) -> left < right ? -1 : left > right ? 1 : 0);
			Sys.println(observations.join("\n"));
		});
	}
}
