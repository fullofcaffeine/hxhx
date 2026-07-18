/** Computes a deterministic summary without relying on the compiler checkout. */
class WorkReport {
	public static function completedCount(items:Array<WorkItem>):Int {
		var count = 0;
		for (item in items) {
			if (item.completed) {
				count++;
			}
		}
		return count;
	}

	public static function completedMinutes(items:Array<WorkItem>):Int {
		var minutes = 0;
		for (item in items) {
			if (item.completed) {
				minutes += item.minutes;
			}
		}
		return minutes;
	}

	public static function pendingNames(items:Array<WorkItem>):Array<String> {
		final pending = new Array<WorkItem>();
		for (item in items) {
			if (!item.completed) {
				pending.push(item);
			}
		}
		pending.sort(compareWork);
		return [for (item in pending) item.name];
	}

	public static function nextItem(items:Array<WorkItem>):String {
		final pending = pendingNames(items);
		return pending.length == 0 ? "none" : pending[0];
	}

	static function compareWork(left:WorkItem, right:WorkItem):Int {
		final priorityOrder = score(left.priority) - score(right.priority);
		return priorityOrder == 0 ? Reflect.compare(left.name, right.name) : priorityOrder;
	}

	static function score(priority:Priority):Int {
		return switch priority {
			case Critical: 0;
			case Normal: 1;
			case Low: 2;
		};
	}
}
