package pk;

/** Values of `Res` get the static extensions of `ResTools` without a `using` line. **/
@:using(pk.Res.ResTools)
enum Res<T> {
	Ok(value:T);
	Err(message:String);
}

class ResTools {
	public static function resolve<T>(result:Res<T>):T {
		return switch result {
			case Ok(value): value;
			case Err(message): throw message;
		}
	}

	public static function isOk<T>(result:Res<T>):Bool {
		return switch result {
			case Ok(_): true;
			case Err(_): false;
		}
	}
}
