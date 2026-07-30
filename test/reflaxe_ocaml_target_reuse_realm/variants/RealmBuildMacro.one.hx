#if macro
import haxe.macro.Context;
import haxe.macro.Expr;
#end

/** First build-macro state used by the reusable-realm fixture. **/
class RealmBuildMacro {
	#if macro
	public static macro function apply():Array<Field> {
		final fields = Context.getBuildFields();
		fields.push({
			name: "marker",
			access: [APublic, AStatic],
			kind: FVar(macro :Int, macro 1),
			pos: Context.currentPos()
		});
		return fields;
	}

	public static macro function failRequest():Expr {
		Context.fatalError("injected target-reuse macro failure", Context.currentPos());
		return macro null;
	}
	#end
}
