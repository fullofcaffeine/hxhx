/** A separate module owns the interface dispatch record. */
interface ICounter {
	function add(amount:Int):Int;
	function read():Int;
}
