package backend.source;

typedef PhpNameNormalizer = String->String;

/**
	Helpers for PHP abstract facade support in the source-native backend.

	Why:
	- The bootstrap parser currently represents local Haxe abstracts as support
	  classes, while some abstract conversions are erased by the time PHP source
	  emission sees call sites.
	- PHP-specific facade repair should not keep growing `SourceTargetCommon`,
	  which should remain the shared dispatcher/rendering seam.

	What:
	- Reads parser-provided abstract metadata.
	- Copies public instance methods from wrapper/facade abstracts onto the
	  emitted backing abstract support class when the source abstract declares
	  that backing type.

	How:
	- `ParserStageScanHelpers` records `__hxhx_abstract_underlying=<Type>` for
	  top-level abstracts.
	- The PHP emitter calls this helper before rendering a support class so
	  values constructed as the backing class can still expose facade methods.
**/
class PhpAbstractFacadeSupport {
	static inline final ABSTRACT_MARKER = "__hxhx_abstract";
	static inline final UNDERLYING_PREFIX = "__hxhx_abstract_underlying=";

	public static function classFunctionsWithFacadeMethods(cls:HxClassDecl, className:String, scanClasses:Array<HxClassDecl>,
			normalizeTypePath:PhpNameNormalizer, normalizeMemberName:PhpNameNormalizer):Array<HxFunctionDecl> {
		final out = HxClassDecl.getFunctions(cls).copy();
		final seen = new Map<String, Bool>();
		for (fn in out)
			seen.set(normalizeMemberName(HxFunctionDecl.getName(fn)), true);
		if (scanClasses == null)
			return out;
		for (facade in scanClasses) {
			if (facade == cls || !hasAbstractMarker(facade))
				continue;
			final underlying = abstractUnderlyingTypeName(facade);
			if (underlying == null || normalizeTypePath(underlying) != className)
				continue;
			for (fn in HxClassDecl.getFunctions(facade)) {
				if (HxFunctionDecl.getIsStatic(fn) || HxFunctionDecl.getName(fn) == "new")
					continue;
				final methodName = normalizeMemberName(HxFunctionDecl.getName(fn));
				if (seen.exists(methodName))
					continue;
				seen.set(methodName, true);
				out.push(fn);
			}
		}
		return out;
	}

	static function hasAbstractMarker(cls:HxClassDecl):Bool {
		for (meta in HxClassDecl.getMetadata(cls))
			if (meta == ABSTRACT_MARKER)
				return true;
		return false;
	}

	static function abstractUnderlyingTypeName(cls:HxClassDecl):Null<String> {
		for (raw in HxClassDecl.getMetadata(cls)) {
			final text = StringTools.trim(raw == null ? "" : raw);
			if (StringTools.startsWith(text, UNDERLYING_PREFIX))
				return text.substr(UNDERLYING_PREFIX.length);
		}
		return null;
	}
}
