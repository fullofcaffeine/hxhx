package hxhx.macro;

private typedef BuildFieldArgPayload = {
	final name:String;
	final isOptional:Bool;
	final isRest:Bool;
	final typeHint:String;
	final defaultValueText:String;
};

private class BuildFieldPayloadItem {
	public final name:String;
	public final kind:String;
	public final isStatic:Bool;
	public final visibility:String;
	public final metadata:Array<String>;
	public final min:Int;
	public final max:Int;
	public final isFinal:Bool;
	public final propertyGet:String;
	public final propertySet:String;
	public final typeHint:String;
	public final initText:String;
	public final args:Array<BuildFieldArgPayload>;
	public final returnTypeHint:String;
	public final bodyText:String;

	public function new(name:String, kind:String, isStatic:Bool, visibility:String, metadata:Array<String>, min:Int, max:Int, isFinal:Bool,
			propertyGet:String, propertySet:String, typeHint:String, initText:String, args:Array<BuildFieldArgPayload>, returnTypeHint:String,
			bodyText:String) {
		this.name = name;
		this.kind = kind;
		this.isStatic = isStatic;
		this.visibility = visibility;
		this.metadata = metadata == null ? [] : metadata;
		this.min = min;
		this.max = max;
		this.isFinal = isFinal;
		this.propertyGet = propertyGet == null ? "" : propertyGet;
		this.propertySet = propertySet == null ? "" : propertySet;
		this.typeHint = typeHint == null ? "" : typeHint;
		this.initText = initText == null ? "" : initText;
		this.args = args == null ? [] : args;
		this.returnTypeHint = returnTypeHint == null ? "" : returnTypeHint;
		this.bodyText = bodyText == null ? "" : bodyText;
	}
}

/**
	Encode the current parsed class member surface into the reverse-RPC payload used by
	`Context.getBuildFields()`.

	Why
	- Stage3 needs a deterministic, compiler-owned snapshot of the fields/functions currently being
	  built so external-host build macros can inspect and return them.
	- Tests also need to exercise this encoder directly without dragging the full `Stage3Compiler`
	  runtime shell into `--interp`.

	What
	- Encodes a narrow but materially useful member snapshot:
	  - name / kind / visibility / static / final
	  - raw metadata texts
	  - source file + min/max span
	  - field/property type + initializer text
	  - function args + arg defaults + return type + raw body text

	Gotchas
	- This is still a parser-backed snapshot, not a typed AST transport.
	- Everything after this point still depends on the runtime side honestly reparsing only the
	  supported subset.
**/
class BuildFieldSnapshotPayload {
	public static function encodeParsedModule(pm:ParsedModule):String {
		final decl = pm.getDecl();
		final cls = HxModuleDecl.getMainClass(decl);
		final items = new Array<BuildFieldPayloadItem>();
		final filePath = pm.getFilePath();

		for (fn in HxClassDecl.getFunctions(cls)) {
			final args = [
				for (arg in HxFunctionDecl.getArgs(fn))
					{
						name: HxFunctionArg.getName(arg),
						isOptional: HxFunctionArg.getIsOptional(arg),
						isRest: HxFunctionArg.getIsRest(arg),
						typeHint: HxFunctionArg.getTypeHint(arg),
						defaultValueText: HxFunctionArg.getDefaultValueText(arg)
					}
			];
			items.push(new BuildFieldPayloadItem(HxFunctionDecl.getName(fn), "fun", HxFunctionDecl.getIsStatic(fn),
				Std.string(HxFunctionDecl.getVisibility(fn)), HxFunctionDecl.getMetadata(fn), HxFunctionDecl.getPos(fn).getIndex(),
				HxFunctionDecl.getEndPos(fn).getIndex(), false, "", "", "", "", args, HxFunctionDecl.getReturnTypeHint(fn), HxFunctionDecl.getBodyText(fn)));
		}
		for (f in HxClassDecl.getFields(cls)) {
			final kind = HxFieldDecl.getPropertyGet(f).length > 0 || HxFieldDecl.getPropertySet(f).length > 0 ? "prop" : "var";
			items.push(new BuildFieldPayloadItem(HxFieldDecl.getName(f), kind, HxFieldDecl.getIsStatic(f), Std.string(HxFieldDecl.getVisibility(f)),
				HxFieldDecl.getMetadata(f), HxFieldDecl.getPos(f).getIndex(), HxFieldDecl.getEndPos(f).getIndex(), HxFieldDecl.getIsFinal(f),
				HxFieldDecl.getPropertyGet(f), HxFieldDecl.getPropertySet(f), HxFieldDecl.getTypeHint(f), HxFieldDecl.getInitText(f), [], "", ""));
		}

		final parts = new Array<String>();
		parts.push(MacroProtocol.encodeLen("f", filePath == null ? "" : filePath));
		parts.push(MacroProtocol.encodeLen("c", Std.string(items.length)));
		for (i in 0...items.length) {
			final it = items[i];
			parts.push(MacroProtocol.encodeLen("n" + i, it.name));
			parts.push(MacroProtocol.encodeLen("k" + i, it.kind));
			parts.push(MacroProtocol.encodeLen("s" + i, it.isStatic ? "1" : "0"));
			parts.push(MacroProtocol.encodeLen("v" + i, it.visibility));
			parts.push(MacroProtocol.encodeLen("mn" + i, Std.string(it.min)));
			parts.push(MacroProtocol.encodeLen("mx" + i, Std.string(it.max)));
			parts.push(MacroProtocol.encodeLen("fi" + i, it.isFinal ? "1" : "0"));
			parts.push(MacroProtocol.encodeLen("pg" + i, it.propertyGet));
			parts.push(MacroProtocol.encodeLen("ps" + i, it.propertySet));
			parts.push(MacroProtocol.encodeLen("th" + i, it.typeHint));
			parts.push(MacroProtocol.encodeLen("ie" + i, it.initText));
			parts.push(MacroProtocol.encodeLen("rt" + i, it.returnTypeHint));
			parts.push(MacroProtocol.encodeLen("bd" + i, it.bodyText));
			parts.push(MacroProtocol.encodeLen("mc" + i, Std.string(it.metadata.length)));
			for (j in 0...it.metadata.length)
				parts.push(MacroProtocol.encodeLen("m" + i + "_" + j, it.metadata[j]));
			parts.push(MacroProtocol.encodeLen("ac" + i, Std.string(it.args.length)));
			for (j in 0...it.args.length) {
				final arg = it.args[j];
				parts.push(MacroProtocol.encodeLen("an" + i + "_" + j, arg.name));
				parts.push(MacroProtocol.encodeLen("ao" + i + "_" + j, arg.isOptional ? "1" : "0"));
				parts.push(MacroProtocol.encodeLen("ar" + i + "_" + j, arg.isRest ? "1" : "0"));
				parts.push(MacroProtocol.encodeLen("at" + i + "_" + j, arg.typeHint));
				parts.push(MacroProtocol.encodeLen("ad" + i + "_" + j, arg.defaultValueText));
			}
		}
		return parts.join(" ");
	}
}
