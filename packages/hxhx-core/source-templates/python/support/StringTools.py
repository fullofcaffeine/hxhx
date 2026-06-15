class StringTools:
    @staticmethod
    def startsWith(value, prefix):
        return str(value).startswith(str(prefix))

    @staticmethod
    def endsWith(value, suffix):
        return str(value).endswith(str(suffix))

    @staticmethod
    def hex(value, digits=None):
        n = int(value)
        if n < 0:
            n = n & 0xffffffff
        text = format(n, "X")
        return text if digits is None else text.rjust(int(digits), "0")
