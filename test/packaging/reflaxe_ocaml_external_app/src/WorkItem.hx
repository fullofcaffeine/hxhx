/** A small application record used by the standalone package smoke test. */
class WorkItem {
	public final name:String;
	public final minutes:Int;
	public final priority:Priority;
	public final completed:Bool;

	public function new(name:String, minutes:Int, priority:Priority, completed:Bool) {
		this.name = name;
		this.minutes = minutes;
		this.priority = priority;
		this.completed = completed;
	}
}
