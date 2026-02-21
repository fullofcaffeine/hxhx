package tink.sql;

import tink.sql.Info.Column;
import tink.sql.Info.Key;
import tink.sql.Query.AlterTableOperation;
import tink.sql.format.Formatter;

/**
 * JS-example-local shim.
 *
 * The `tink_sql` alpha used in this example includes schema diff code that
 * pulls non-JS driver modules during typing. We only need typed query/format
 * APIs in this example, not schema diffing, so this keeps the surface minimal.
 */
class Schema {
	final columns:Array<Column>;
	final keys:Array<Key>;

	public function new(columns:Iterable<Column>, keys:Iterable<Key>) {
		this.columns = [for (column in columns) column];
		this.keys = [for (key in keys) key];
	}

	public function diff(_:Schema, __:Formatter<{}, {}>):Array<AlterTableOperation>
		return [];
}
