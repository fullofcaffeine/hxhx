import haxe.macro.Context;
import haxe.macro.Expr;

/**
	Upstream side of the frontend parse oracle. Runs as a compiler macro inside upstream Haxe 4.3.7.

	A global build macro records the parsed body of every class, enum and abstract field that the
	compilation loads, before typing. Bodies are printed with `haxe.macro.Printer`, which ignores
	positions. Upstream Haxe is used only as a black box here: nothing from its sources is copied.

	Bodies pass through `ParseOracleNormalize`, the same normalizer the hxhx side uses.
**/
class ParseOracleUpstream {
	static final records:Array<{
		key:String,
		file:String,
		?body:String,
		?error:String
	}> = [];
	static var written = false;

	/** Install the recorder; `out` receives `{defines, records}` as JSON after typing. */
	public static function install(out:String):Void {
		haxe.macro.Compiler.addGlobalMetadata("", "@:build(ParseOracleUpstream.record())", true, true, false);
		Context.onAfterTyping(_ -> {
			if (written)
				return;
			written = true;
			final defines = Context.getDefines();
			final defineList = [for (key in defines.keys()) {name: key, value: defines.get(key)}];
			sys.io.File.saveContent(out, haxe.Json.stringify({defines: defineList, records: records}));
		});
	}

	public static function record():Null<Array<Field>> {
		final owner:Null<{module:String, name:String, pos:Position}> = switch Context.getLocalType() {
			// An abstract's fields are built on its implementation class `Name_Impl_`; record them under the abstract's name.
			case TInst(c, _): {
					module: c.get().module,
					name: StringTools.endsWith(c.get().name, "_Impl_") ? c.get().name.substr(0, c.get().name.length - 6) : c.get().name,
					pos: c.get().pos
				};
			case TEnum(e, _): {module: e.get().module, name: e.get().name, pos: e.get().pos};
			case TAbstract(a, _): {module: a.get().module, name: a.get().name, pos: a.get().pos};
			case _: null;
		}
		if (owner == null)
			return null;
		final printer = new haxe.macro.Printer();
		final file = Context.getPosInfos(owner.pos).file;
		for (field in Context.getBuildFields()) {
			final body = switch field.kind {
				case FFun(fn): fn.expr;
				case FVar(_, value) | FProp(_, _, _, value): value;
			}
			if (body == null)
				continue;
			final key = owner.module + "." + owner.name + "." + field.name;
			try {
				records.push({key: key, file: file, body: printer.printExpr(ParseOracleNormalize.expr(body))});
			} catch (e:haxe.Exception) {
				records.push({key: key, file: file, error: "upstream printer: " + e.message});
			}
		}
		return null;
	}
}
