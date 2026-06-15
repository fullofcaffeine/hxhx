class Compiler:
    __hx_defines = {}

    @staticmethod
    def getDefine(key):
        return Compiler.__hx_defines.get(key, None)

    @staticmethod
    def define(key, value="1"):
        Compiler.__hx_defines[key] = value

    @staticmethod
    def excludeFile(path):
        return None
