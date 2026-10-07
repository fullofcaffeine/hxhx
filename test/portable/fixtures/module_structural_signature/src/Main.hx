/** Checks copied values, width subtyping, optional fields, and mutation through an alias. */
class Main {
	static function main():Void {
		final source = {value: 7, label: "kept", extra: true};
		final copied = First.copy(source);
		Sys.println(copied.value);
		Sys.println(copied.label == null);
		final alias = Second.update(source);
		Sys.println(source.value);
		Sys.println(alias == source);
		Sys.println(alias.label);
		Sys.println(source.extra);
		Sys.println(First.withToken(source, new Token(3)).value);
		Sys.println(First.scopes(source)[0][0].value);
		Sys.println(First.scopes(source, null)[0][0].value);
		final groups = [[new Token(4)]];
		final returned = First.scopes(source, groups);
		Sys.println(returned == groups);
		returned[0].push(new Token(5));
		Sys.println(groups[0].length);
		Sys.println(First.scopes(source, []).length);
		final receiver = new Token(3);
		final other = new Token(4);
		if (receiver.getLinked() != null || receiver.label() != null || receiver.label("alone") != "alone")
			throw "initial nullable method result changed";
		receiver.setLinked(other);
		if (receiver.getLinked() != other || other.getLinked() != null || receiver.label() != "linked")
			throw "method receiver state was not isolated";
		receiver.setLinked(null);
		if (receiver.getLinked() != null || receiver.label(null) != null)
			throw "explicit null method argument changed";
		final values = receiver.getValues();
		if (values != receiver.values)
			throw "method array result lost its identity";
		receiver.append([9]);
		if (values.length != 2 || values[1] != 9 || other.getValues().length != 1)
			throw "array method parameter or receiver mutation changed";
		Sys.println("methods-ok");
		if (First.maybe(source, false) != null || First.maybe(source, true) != source)
			throw "nullable record result changed";
		final holder = First.hold(source);
		if (holder.item != source || First.hold().item.value != 5 || First.hold(null).item.value != 5)
			throw "optional record constructor changed";
		holder.item.value = 11;
		if (source.value != 11)
			throw "record constructor lost its alias";
		Sys.println("nullable-records-ok");
		if (First.floatIdentity(1.25) != 1.25 || First.floatIdentity(-2.5) != -2.5)
			throw "finite Float declaration changed its value";
		Sys.println("float-declarations-ok");
	}
}
