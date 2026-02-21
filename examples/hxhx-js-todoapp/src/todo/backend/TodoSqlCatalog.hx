package todo.backend;

import StringTools;
import tink.core.Any;
import tink.core.Noise;
import tink.core.Promise;
import tink.sql.Connection;
import tink.sql.DatabaseDefinition;
import tink.sql.OrderBy.Order;
import tink.sql.Query;
import tink.sql.Transaction;
import tink.sql.Types;
import tink.sql.format.Sanitizer;
import tink.sql.format.SqlFormatter;
import todo.shared.TodoTypes.TodoItem;

class TodoSqlCatalog {
	static final FORMATTER:SqlFormatter<{}, {}> = new SqlFormatter();
	static final SANITIZER:Sanitizer = new TodoSqlSanitizer();

	public static function createTableSql():String {
		final tx = previewTx();
		return renderQuery(CreateTable(tx.TodoItem.info, false));
	}

	public static function seedInsertSql(items:Array<TodoItem>):Array<String> {
		final tx = previewTx();
		return [for (item in items) renderInsert(tx, item)];
	}

	public static function openTodosSelectSql(limit:Int):String {
		final tx = previewTx();
		final query = tx.TodoItem.where(row -> !row.done).orderBy(row -> [{field: row.created_at, order: Asc}]).limit(limit);
		return renderQuery(@:privateAccess query.toQuery());
	}

	static function renderInsert(tx:TodoSqlPreviewTx, item:TodoItem):String {
		final row:TodoSqlRow = {
			id: cast item.id,
			title: item.title,
			description: item.description,
			done: item.done,
			created_at: item.createdAt,
		};
		return renderQuery(Insert({
			table: tx.TodoItem.info,
			data: Literal([row]),
		}));
	}

	static function previewTx():TodoSqlPreviewTx
		return new TodoSqlPreviewTx(new TodoSqlPreviewConnection());

	static function renderQuery<Result>(query:Query<TodoSqlSchema, Result>):String
		return FORMATTER.format(query).toString(SANITIZER);
}

private typedef TodoSqlRow = {
	@:autoIncrement @:primary var id(default, null):Id<TodoSqlRow>;
	var title(default, null):VarChar<160>;
	var description(default, null):VarChar<512>;
	var done(default, null):Bool;
	var created_at(default, null):VarChar<32>;
}

private interface TodoSqlSchema extends DatabaseDefinition {
	@:table('todo_item') var TodoItem:TodoSqlRow;
}

private typedef TodoSqlPreviewTx = Transaction<TodoSqlSchema>;

private class TodoSqlPreviewConnection implements Connection<TodoSqlSchema> {
	final formatter:SqlFormatter<{}, {}> = new SqlFormatter();

	public function new() {}

	public function getFormatter()
		return formatter;

	public function execute<Result>(query:Query<TodoSqlSchema, Result>):Result
		throw 'TodoSqlPreviewConnection cannot execute queries';

	public function executeSql(sql:String):Promise<Noise>
		throw 'TodoSqlPreviewConnection cannot execute raw SQL';
}

private class TodoSqlSanitizer implements Sanitizer {
	public function new() {}

	public function value(v:Any):String {
		if (v == null)
			return 'null';
		if (Std.isOfType(v, Bool))
			return (cast v : Bool) ? 'true' : 'false';
		if (Std.isOfType(v, Int) || Std.isOfType(v, Float))
			return Std.string(v);
		return quote(Std.string(v));
	}

	public function ident(s:String):String
		return '`' + StringTools.replace(s, '`', '``') + '`';

	static function quote(v:String):String
		return '"' + StringTools.replace(v, '"', '\\"') + '"';
}
