package todo.shared;

enum abstract TodoFilter(String) to String {
	var All = "all";
	var Open = "open";
	var Done = "done";
}

typedef TodoItem = {
	final id:Int;
	final title:String;
	final description:String;
	final done:Bool;
	final createdAt:String;
}

typedef CreateTodoInput = {
	var title:String;
	var description:String;
}
