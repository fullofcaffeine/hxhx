/** A service object retains typed callbacks as well as its own value across cache resets. */
class ServiceState {
	public final value:Int;

	final services:Cache.Service;

	public function new(value:Int, services:Cache.Service) {
		this.value = value;
		this.services = services;
	}

	public function apply(input:Int):Int
		return services.apply(input);
}
