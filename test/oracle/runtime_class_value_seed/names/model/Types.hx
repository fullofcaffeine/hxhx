package model;

/** Exposes a private secondary class handle through its owning module. */
class Types {
	public static function hidden():Class<PrivateLeaf>
		return PrivateLeaf;
}

/** Public secondary declaration with a reflection name outside its module path. */
class PublicLeaf {
	public function new() {}
}

/** Private secondary declaration whose reflection name includes the private module. */
private class PrivateLeaf {
	public function new() {}
}
