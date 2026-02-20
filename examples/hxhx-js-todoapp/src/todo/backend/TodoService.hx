package todo.backend;

import todo.shared.TodoContract.TodoApi;
import todo.shared.TodoTypes.CreateTodoInput;
import todo.shared.TodoTypes.TodoItem;

class TodoService implements TodoApi {
	final todos:Array<TodoItem> = [];
	var nextId:Int = 1;

	public function new() {}

	public function seedDefaults():Void {
		create({title: "Ship hxhx JS example", description: "Build the end-to-end todo demo."});
		create({title: "Document stage model", description: "Explain stage0/stage3 in beginner-friendly terms."});
		create({title: "Polish UI experience", description: "Improve spacing, motion, and empty-state copy."});
	}

	@:get('/todos')
	public function list():Array<TodoItem>
		return [for (todo in todos) cloneTodo(todo)];

	@:post('/todos')
	public function create(body:CreateTodoInput):TodoItem {
		final createdAt = '2026-02-${pad2(nextId)}T09:30:00Z';
		final next:TodoItem = {
			id: nextId,
			title: body.title,
			description: body.description,
			done: false,
			createdAt: createdAt,
		};
		nextId++;
		todos.push(next);
		return cloneTodo(next);
	}

	@:post('/todos/$id/toggle')
	public function toggle(id:Int):TodoItem {
		final idx = indexOf(id);
		if (idx < 0)
			throw 'Todo not found: $id';

		final current = todos[idx];
		final updated:TodoItem = {
			id: current.id,
			title: current.title,
			description: current.description,
			done: !current.done,
			createdAt: current.createdAt,
		};
		todos[idx] = updated;
		return cloneTodo(updated);
	}

	@:delete('/todos/$id')
	public function remove(id:Int):{deleted:Bool} {
		final idx = indexOf(id);
		if (idx < 0)
			return {deleted: false};

		todos.splice(idx, 1);
		return {deleted: true};
	}

	public function doneCount():Int {
		var count = 0;
		for (todo in todos) {
			if (todo.done)
				count++;
		}
		return count;
	}

	public function openCount():Int
		return todos.length - doneCount();

	public function openSlugs():Array<String>
		return [for (todo in todos) if (!todo.done) slug(todo.title)];

	function indexOf(id:Int):Int {
		for (idx in 0...todos.length) {
			if (todos[idx].id == id)
				return idx;
		}
		return -1;
	}

	static function cloneTodo(todo:TodoItem):TodoItem {
		return {
			id: todo.id,
			title: todo.title,
			description: todo.description,
			done: todo.done,
			createdAt: todo.createdAt,
		};
	}

	static function slug(value:String):String {
		final lowered = value.toLowerCase();
		final words = lowered.split(" ");
		return words.join("-");
	}

	static function pad2(value:Int):String
		return value < 10 ? "0" + value : Std.string(value);
}
