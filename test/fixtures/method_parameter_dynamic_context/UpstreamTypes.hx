import haxe.macro.Context;
import haxe.macro.Type;

/** Observe stock Haxe's public parameter types after it has checked the bodies. */
class UpstreamTypes {
	public static function check():Void {
		Context.onAfterTyping(_ -> {
			final observations:Array<String> = [];
			switch Context.getType("Main") {
				case TInst(reference, _):
					for (field in reference.get().statics.get())
						switch Context.follow(field.type) {
							case TFun(arguments, _):
								for (argument in arguments) {
									final type = switch Context.follow(argument.t) {
										case TMono(cell) if (cell.get() == null): "Unknown";
										case other: haxe.macro.TypeTools.toString(other);
									};
									observations.push(field.name + "." + argument.name + "=" + type);
								}
							case _: throw "fixture requires static functions";
						}
				case _: throw "fixture requires the Main class";
			}
			observations.sort((left, right) -> left < right ? -1 : left > right ? 1 : 0);
			Sys.println(observations.join("\n"));
		});
	}
}
