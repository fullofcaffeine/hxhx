import todo.backend.TodoService;
import todo.backend.TodoSqlCatalog;
import todo.backend.TodoSqlCatalog.TodoTableInfo;
import todo.frontend.TodoAppView;
import tink.web.routing.Router;
#if js
import coconut.ui.Renderer;
import coconut.Ui.hxx;
import js.Browser;
import js.Syntax;
#end

class Main {
	static function main() {
		final service = new TodoService();
		service.seedDefaults();
		service.toggle(2);
		service.create({
			title: "Write release notes",
			description: "Summarize what shipped and what still needs stage polish.",
		});
		service.remove(3);

		final routerReady = new Router<TodoService>(service) != null;
		final todos = service.list();
		final done = service.doneCount();
		final open = service.openCount();
		final openSlugs = service.openSlugs().join(",");

		final createSql = TodoSqlCatalog.createTableSql(new TodoTableInfo());
		final inserts = TodoSqlCatalog.seedInsertSql(todos);

		printLine('router=' + (routerReady ? 'ready' : 'missing'));
		printLine('todo-count=' + todos.length);
		printLine('done-count=' + done);
		printLine('open-count=' + open);
		printLine('open-slugs=' + openSlugs);
		printLine('sql-ddl=' + createSql);
		printLine('sql-insert-1=' + inserts[0]);
		printLine('sql-insert-2=' + inserts[1]);

		#if js
		mountBrowserUi();
		#end
	}

	#if js
	static function mountBrowserUi():Void {
		final hasDom:Bool = Syntax.code("typeof document !== 'undefined' && !!document.getElementById");
		if (!hasDom)
			return;

		final mountPoint = Browser.document.getElementById("app");
		if (mountPoint == null)
			return;

		Renderer.mount(cast mountPoint, hxx('<TodoAppView title="HXHX Todo Command Center" />'));
	}
	#end

	static function printLine(value:String):Void {
		#if js
		js.Lib.global.console.log(value);
		#else
		Sys.println(value);
		#end
	}
}
