package;

#if macro
import haxe.macro.Context;
import haxe.macro.Expr;
#end

/** Adds one deterministic String field for the server macro-rebuild fixture. **/
class BuildMacro {
	#if macro
	public static function addGeneratedField():Array<Field> {
		final fields = Context.getBuildFields();
		fields.push({
			name: "generated",
			access: [APublic, AStatic],
			kind: FFun({
				args: [],
				ret: macro :String,
				expr: macro return "macro-a"
			}),
			pos: Context.currentPos()
		});
		return fields;
	}
	#end
}
