class Type:
    _hx_class_name = "Type"
    @staticmethod
    def getClass(value):
        # Class objects and anonymous records have no Haxe class.
        if value is None or isinstance(value, type) or type(value).__name__ == "HxAnon":
            return None
        return value.__class__

    @staticmethod
    def getClassName(cls):
        if cls is None:
            return None
        target = cls if isinstance(cls, type) else cls.__class__
        # Emitted and runtime classes carry their full dotted Haxe path.
        name = getattr(target, "_hx_class_name", None)
        if name is not None:
            return name
        if target is str:
            return "String"
        if target is list:
            return "Array"
        raise TypeError("hxhx Python has no Haxe class name for " + str(target))
