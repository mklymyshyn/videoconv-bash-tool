import os
import sys
import logging
import subprocess

class VideoconvWrapper(object):
    tool_path = "bin/convert-video.sh"
    debug = False
    
    def __init__(self, tool_path = None, conv_id = None, source_video = None,
                 debug = False):
        self._options = {}
        
        self.debug = debug
        
        if tool_path:
            self.tool_path = tool_path
            
        if conv_id != None:
            self.option("q", conv_id)
            
        if source_video !=None:
            self.option("i", source_video)
    
    def set_video(self, path):
        self.option('i', path)
        
    def get_video(self):
        return self.get_option("i")
        
    def set_destination_video(self, path):
        self.option('o', path)
        
    def get_option(self, name):
        if name in self._options.keys():
            return self._options[name]
        return ''
        
    def option(self, arg, value = ''):
        self._options[arg] = value;
    
    def options(self, options):
        for name, val in options.iteritems():
            self._options[name] = val
            
    def _pair(self, args, name = "h"):
        if name in self._options.keys():
            if self._options[name] != '':
                args.append('-%s' % name)
                args.append(str(self._options[name]))
                return ""
            args.append('-%s' % name)
        return ""

    def execute_cmd(self, args):        
        args.insert(0, self.tool_path)
        if self.debug:
            print "Command: %s" % " ".join(args)
            
        p = subprocess.Popen(" ".join(args), shell = True, stdout = subprocess.PIPE)
        return (p.stdin, p.stdout)
        
    def convert(self):
        args = []
        map(lambda key: self._pair(args, key), self._options.keys())
        (stdin, stdout) = self.execute_cmd(args)
        output = stdout.read()
        error_prefix = "ERROR:"
        
        if output[0:len(error_prefix)] == error_prefix:
            raise ValueError, "Can't convert video. Reason: %s" % output

    def unregister(self):
        args = ['-u']
        self._pair(args, name = "q")

        (stdin, stdout) = self.execute_cmd(args)
        return stdout.read()
        
        
    def info(self, file = None):        
        args = ['-j']
        if not file:
            self._pair(args, name = "q")
        else:
            self._pair(args, name = "i")

        (stdin, stdout) = self.execute_cmd(args)
        #    raise ValueError, "Can't get information about video. Reason: %s" % str(e)
        
        reply_pairs = [obj.split('=') for obj in stdout.read().split("\n") if obj != '']
        reply_dict = {}
        
        for item in reply_pairs:
            key, val = tuple(item)
            reply_dict[key.lower()] = val
        
        class ReplyDict(object):
            def __init__(self, data = {}):
                self._keys = data.keys()
                self.__dict__.update(data)

            def keys(self):
                return self._keys
                
        return ReplyDict(reply_dict)
    

    
def testing():
    conv_id = "12"
    conv = VideoconvWrapper(conv_id = conv_id)
    conv.set_video("iamlegend.mov")
    conv.set_destination_video("test.mp4")


    #info = conv.info()
    #print "Info keys: %s" % ", ".join(info.keys())
    #print "Duration: %s" % info.duration
    
    conv.options({
        't' : 'mp4', # type of encoding
        'p' : '704x576', # max dimension
        'e' : '', # two-pass encoding
        'r' : '', # using delayed conversion
        'c' : '' # generate thumbnails after conversion
    })

    conv.convert()
    #conv.unregister()
    
if __name__ == "__main__":
    testing()
    