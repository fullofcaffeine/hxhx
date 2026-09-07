package backend.ocaml;

import haxe.ds.StringMap;

/**
	Assigns collision-free OCaml names to exact typed bindings in one body.

	The shared projection has already separated shadowed Haxe bindings by identity.
	This target-owned pass preserves that separation after OCaml keyword escaping or
	case normalization. The synthetic instance receiver is reserved independently
	and never becomes a typed local. Function bodies and field initializers each
	supply their own catalog; this pass never recovers bindings from source text.
**/
class Stage3OcamlLocalNames {
	final byProjectedName:StringMap<String>;
	final localCatalog:TypedBackendLocalCatalog;

	public function new(localCatalog:TypedBackendLocalCatalog, hasInstanceReceiver:Bool, normalize:String->String) {
		if (localCatalog == null)
			throw "Stage3 OCaml local naming requires a typed local catalog";
		if (normalize == null)
			throw "Stage3 OCaml local naming requires a target normalizer";
		this.localCatalog = localCatalog;
		byProjectedName = new StringMap<String>();
		final used = new StringMap<Bool>();
		if (hasInstanceReceiver)
			used.set("this_", true);
		for (entry in localCatalog.getEntries()) {
			final projectedName = entry.getProjectedName();
			final base = normalize(projectedName);
			if (base == null || base.length == 0 || base == "_")
				throw "Stage3 OCaml local naming cannot render exact binding " + entry.getBinding().getIdentity().getCanonicalKey();
			var targetName = base;
			var suffix = 0;
			while (used.exists(targetName)) {
				suffix++;
				targetName = base + "_" + suffix;
			}
			used.set(targetName, true);
			byProjectedName.set(projectedName, targetName);
		}
	}

	/** Return the target name only when the projected identifier is an exact local. **/
	public function findTargetName(projectedName:String):Null<String>
		return projectedName == null ? null : byProjectedName.get(projectedName);

	/** Keep Unknown distinct from an absent binding when selecting a local's type. **/
	public function findType(projectedName:String):Null<TyType> {
		final local = localCatalog.findByProjectedName(projectedName);
		return local == null ? null : local.getBinding().getType();
	}

	/** Fail when a caller asks for a binding outside the sealed function catalog. **/
	public function targetName(projectedName:String):String {
		final resolved = findTargetName(projectedName);
		if (resolved == null)
			throw "Stage3 OCaml local naming is missing projected binding " + projectedName;
		return resolved;
	}
}
