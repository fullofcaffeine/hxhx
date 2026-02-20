package todo.shared;

import todo.shared.TodoTypes.CreateTodoInput;
import todo.shared.TodoTypes.TodoItem;

interface TodoApi {
	@:get('/todos')
	function list():Array<TodoItem>;

	@:post('/todos')
	function create(body:CreateTodoInput):TodoItem;

	@:post('/todos/$id/toggle')
	function toggle(id:Int):TodoItem;

	@:delete('/todos/$id')
	function remove(id:Int):{deleted:Bool};
}
