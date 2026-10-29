class Type:
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
        return getattr(target, "__name__", str(target))
