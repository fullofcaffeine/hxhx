/**
	The runtime name of one indexed class or enum, independent of import spelling.

	Public secondary types use the package and declared name. Private types also
	include their private module segment. An authored native name replaces that
	default. Indexing freezes this result before mutable source metadata reaches
	a backend; targets must not derive it from compiler declaration identifiers.

	Extern values belong to the host, and specialized generic classes need their
	actual generated declaration. Neither can borrow an ordinary reflected name.
	Their rejection remains local to reflection, so type-only uses still work.
 */
class TyPublicReflectionName {
	final owner:String;
	final name:String;
	final unavailableReason:Null<String>;
	final canonicalIdentity:String;

	public function new(info:TyClassInfo, metadata:Array<String>) {
		owner = info.getIdentity().getCanonicalName();
		final modulePath = info.getModulePath();
		final separator = modulePath.lastIndexOf(".");
		final packagePrefix = separator < 0 ? "" : modulePath.substr(0, separator + 1);
		final moduleName = modulePath.substr(separator + 1);
		final defaultName = packagePrefix + (info.getVisibility() == HxVisibility.Private ? "_" + moduleName + "." : "") + info.getShortName();
		var nativeName:Null<String> = null;
		var unsupported:Null<String> = info.getIsExtern() ? "extern reflection requires a target-owned runtime identity" : null;
		for (entry in metadata) {
			var text = StringTools.trim(entry);
			while (StringTools.startsWith(text, "@") || StringTools.startsWith(text, ":"))
				text = text.substr(1);
			final opening = text.indexOf("(");
			final key = StringTools.trim(opening < 0 ? text : text.substr(0, opening));
			switch (key) {
				case "native":
					final parsedName = switch (HxParser.parseCompleteExprText(text)) {
						case ECall(EIdent("native"), [EString(value)]): value;
						case _: throw "public reflection native metadata requires one literal string: " + owner;
					};
					if (nativeName != null && nativeName != parsedName)
						unsupported = "conflicting native reflection names";
					nativeName = parsedName;
				case "generic", "genericBuild":
					unsupported = "specialized generic reflection requires its generated declaration";
				case "nativeGen", "realPath":
					unsupported = key + " reflection requires an explicit runtime identity";
				case _:
			}
		}
		name = nativeName == null ? defaultName : nativeName;
		unavailableReason = unsupported;
		canonicalIdentity = CompilerCacheIdentity.encode(["public-reflection-name-v1", owner, name, unavailableReason]);
	}

	/** Fail before a target publishes a guessed name for an unsupported representation. */
	public function requireName():String {
		if (unavailableReason != null)
			throw unavailableReason + ": " + owner;
		return name;
	}

	/** Both a changed name and changed reflection availability invalidate derived descriptors. */
	public function getCanonicalIdentity():String
		return canonicalIdentity;
}
