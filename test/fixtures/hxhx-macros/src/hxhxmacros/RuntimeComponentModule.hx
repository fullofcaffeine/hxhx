package hxhxmacros;

import hxhxmacros.RuntimeComponentSupport.Assigns;
import hxhxmacros.RuntimeComponentSupport.Slot;

typedef HeaderSlotProps = {
	var label:String;
}

typedef HeaderLet = {
	var count:Int;
	var userName:String;
}

typedef CardAssigns = {
	var title:String;
	@:slot var header:Slot<HeaderSlotProps, HeaderLet>;
	var inner_content:String;
}

class Components {
	public static function card(assigns:Assigns<CardAssigns>):String {
		return assigns.title;
	}
}
