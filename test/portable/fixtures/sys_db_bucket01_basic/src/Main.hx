#if macro
import haxe.macro.Compiler;
import haxe.macro.Context;

class SysDbBucket01MacroProbe {
	static inline final PREFIX = "HX_SYS_DB_BUCKET01_";
	static final MODULES:Array<String> = ["sys.db.Connection", "sys.db.Mysql", "sys.db.ResultSet", "sys.db.Sqlite"];

	static function defineKey(moduleName:String):String {
		return PREFIX + moduleName.toUpperCase().split(".").join("_");
	}

	public static function run():Void {
		for (moduleName in MODULES) {
			final moduleTypes = Context.getModule(moduleName);
			if (moduleTypes == null || moduleTypes.length == 0) {
				Context.fatalError("sys_db_bucket01_basic: missing module " + moduleName, Context.currentPos());
			}
			Compiler.define(defineKey(moduleName), "1");
		}
		Compiler.define("HX_SYS_DB_BUCKET01_DONE", "1");
	}
}
#end

class Main {
	static function printStatus(name:String, ok:Bool):Void {
		Sys.println(name + "=" + (ok ? "ok" : "missing"));
	}

	static function main() {
		#if HX_SYS_DB_BUCKET01_SYS_DB_CONNECTION
		printStatus("sys.db.Connection", true);
		#else
		printStatus("sys.db.Connection", false);
		#end

		#if HX_SYS_DB_BUCKET01_SYS_DB_MYSQL
		printStatus("sys.db.Mysql", true);
		#else
		printStatus("sys.db.Mysql", false);
		#end

		#if HX_SYS_DB_BUCKET01_SYS_DB_RESULTSET
		printStatus("sys.db.ResultSet", true);
		#else
		printStatus("sys.db.ResultSet", false);
		#end

		#if HX_SYS_DB_BUCKET01_SYS_DB_SQLITE
		printStatus("sys.db.Sqlite", true);
		#else
		printStatus("sys.db.Sqlite", false);
		#end

		final mysqlClassName = Type.getClassName(sys.db.Mysql);
		final sqliteClassName = Type.getClassName(sys.db.Sqlite);
		Sys.println("sys.db.Mysql.class=" + mysqlClassName);
		Sys.println("sys.db.Sqlite.class=" + sqliteClassName);

		#if HX_SYS_DB_BUCKET01_DONE
		Sys.println("sys.db.bucket01=done");
		#else
		Sys.println("sys.db.bucket01=missing");
		#end
	}
}
