#if macro
import haxe.macro.Context;
import haxe.macro.Expr;
#end

/** Macros for the build-metadata cases. Each adds what the declaration does not spell out. */
class ArityMacros {
	#if macro
	public static function addConstructor():Array<Field> {
		final fields = Context.getBuildFields();
		fields.push({
			name: "new",
			access: [APublic],
			pos: Context.currentPos(),
			kind: FFun({args: [{name: "value", type: macro :Int}], expr: macro {}})
		});
		return fields;
	}

	public static function anyArguments():ComplexType {
		return macro :Holder<Int>;
	}
	#end
}
