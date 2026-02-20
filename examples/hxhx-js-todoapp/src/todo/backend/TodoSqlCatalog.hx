package todo.backend;

import tink.sql.Info;
import todo.shared.TodoTypes.TodoItem;
import StringTools;

class TodoSqlCatalog {
	public static function createTableSql(table:TableInfo):String {
		final cols = [for (column in table.getColumns()) columnSql(column)];
		final keys = [for (key in table.getKeys()) keySql(key)];
		final allParts = cols.concat(keys);
		return 'CREATE TABLE ' + ident(table.getName()) + ' (' + allParts.join(', ') + ')';
	}

	public static function seedInsertSql(items:Array<TodoItem>):Array<String>
		return [for (item in items) insertSql(item)];

	static function insertSql(item:TodoItem):String {
		return 'INSERT INTO `todo_item` (`id`, `title`, `description`, `done`, `created_at`) VALUES ('
			+ item.id
			+ ', '
			+ quote(item.title)
			+ ', '
			+ quote(item.description)
			+ ', '
			+ (item.done ? 'true' : 'false')
			+ ', '
			+ quote(item.createdAt)
			+ ')';
	}

	static function columnSql(column:Column):String {
		final nullable = column.nullable ? 'NULL' : 'NOT NULL';
		return ident(column.name) + ' ' + dataTypeSql(column.type) + ' ' + nullable;
	}

	static function keySql(key:Key):String {
		return switch key {
			case Primary(fields):
				'PRIMARY KEY (' + fields.map(ident).join(', ') + ')';
			case Unique(name, fields):
				'UNIQUE KEY ' + ident(name) + ' (' + fields.map(ident).join(', ') + ')';
			case Index(name, fields):
				'KEY ' + ident(name) + ' (' + fields.map(ident).join(', ') + ')';
		}
	}

	static function dataTypeSql(dataType:DataType):String {
		return switch dataType {
			case DBool(_):
				'BOOLEAN';
			case DInt(_, signed, autoIncrement, _):
				(signed ? 'INT' : 'INT UNSIGNED') + (autoIncrement ? ' AUTO_INCREMENT' : '');
			case DDouble(_):
				'DOUBLE';
			case DString(maxLength, _):
				'VARCHAR(' + maxLength + ')';
			case DText(size, _):
				switch size {
					case Tiny:
						'TINYTEXT';
					case Default:
						'TEXT';
					case Medium:
						'MEDIUMTEXT';
					case Long:
						'LONGTEXT';
				}
			case DJson:
				'JSON';
			case DBlob(_):
				'BLOB';
			case DDate(_):
				'DATE';
			case DDateTime(_):
				'DATETIME';
			case DTimestamp(_):
				'TIMESTAMP';
			case DPoint:
				'POINT';
			case DLineString:
				'LINESTRING';
			case DPolygon:
				'POLYGON';
			case DMultiPoint:
				'MULTIPOINT';
			case DMultiLineString:
				'MULTILINESTRING';
			case DMultiPolygon:
				'MULTIPOLYGON';
			case DUnknown(type, _):
				type;
		}
	}

	static function ident(value:String):String
		return '`' + value + '`';

	static function quote(value:String):String
		return '"' + StringTools.replace(value, '"', '\\"') + '"';
}

class TodoTableInfo implements TableInfo {
	public function new() {}

	public function getName():String
		return 'todo_item';

	public function getAlias():String
		return null;

	public function getColumns():Iterable<Column>
		return [
			{
				name: 'id',
				nullable: false,
				writable: false,
				type: DInt(Default, false, true)
			},
			{
				name: 'title',
				nullable: false,
				writable: true,
				type: DString(160)
			},
			{
				name: 'description',
				nullable: false,
				writable: true,
				type: DText(Default)
			},
			{
				name: 'done',
				nullable: false,
				writable: true,
				type: DBool(false)
			},
			{
				name: 'created_at',
				nullable: false,
				writable: true,
				type: DDateTime()
			},
		];

	public function columnNames():Iterable<String>
		return [for (column in getColumns()) column.name];

	public function getKeys():Iterable<Key>
		return [Primary(['id'])];
}
