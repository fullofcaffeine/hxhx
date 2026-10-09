/** A method and a module function form a function-only recursive dependency. */
private class Steps {
	public function new() {}

	public function descend(remaining:Int):Int {
		return remaining == 0 ? 0 : 1 + visit(this, remaining - 1);
	}
}

private function visit(steps:Steps, remaining:Int):Int {
	return steps.descend(remaining);
}

function count(remaining:Int):Int {
	return visit(new Steps(), remaining);
}
