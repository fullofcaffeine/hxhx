/**
	Freeze an authored native symbol at declaration indexing time. The value is
	target-neutral metadata, not permission to use a particular host representation.
	A backend must still validate the target spelling, ownership, and call ABI.
 */
class TyNativeName {
	final name:Null<String>;
	final conflict:Bool;
	final identity:String;

	public function new(metadata:Array<String>) {
		var selected:Null<String> = null;
		var conflicting = false;
		for (entry in (metadata == null ? [] : metadata)) {
			var text = StringTools.trim(entry);
			while (StringTools.startsWith(text, "@") || StringTools.startsWith(text, ":"))
				text = text.substr(1);
			final opening = text.indexOf("(");
			if (StringTools.trim(opening < 0 ? text : text.substr(0, opening)) != "native")
				continue;
			final parsed = switch HxParser.parseCompleteExprText(text) {
				case ECall(EIdent("native"), [EString(value)]): value;
				case _: throw "native metadata requires one literal string";
			};
			conflicting = conflicting || selected != null && selected != parsed;
			selected = parsed;
		}
		name = selected;
		conflict = conflicting;
		identity = CompilerCacheIdentity.encode(["native-name-v1", name, conflict ? "conflict" : "unique"]);
	}

	/** Absence preserves the target's ordinary naming contract; conflicts never select a symbol. */
	public function getName():Null<String> {
		if (conflict)
			throw "conflicting native names";
		return name;
	}

	public function hasConflict():Bool
		return conflict;

	public function getCanonicalIdentity():String
		return identity;
}
