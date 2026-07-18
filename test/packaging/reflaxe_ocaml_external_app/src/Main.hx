/** Entry point for the external reflaxe.ocaml package installation proof. */
class Main {
	static function main() {
		final items = [
			new WorkItem("write-guide", 25, Normal, false),
			new WorkItem("ship-runtime", 50, Critical, true),
			new WorkItem("fix-parser", 20, Critical, false),
			new WorkItem("add-tests", 30, Normal, true)
		];
		final pending = WorkReport.pendingNames(items);
		Sys.println("completed=" + WorkReport.completedCount(items) + "/" + items.length);
		Sys.println("completed_minutes=" + WorkReport.completedMinutes(items));
		Sys.println("pending=" + pending.join(","));
		Sys.println("next=" + WorkReport.nextItem(items));
	}
}
