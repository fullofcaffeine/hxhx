package callers;

import macros.Macros as M;
import macros.Macros.items;

class Aliased {
	static function viaAlias():Int {
		return M.items();
	}

	static function viaImport():Int {
		return items();
	}
}
