import os
import sys
import logging
import subprocess

class VideoconvWrapper(object):
    tool_path = "bin/convert-video.sh"
    debug = False
    error_prefix = "ERROR:"
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
        
    def handle_errors(self, data):
        # split output to lines and check every line for error message
        for line in data.split("\n"):
            if line[0:len(self.error_prefix)] == self.error_prefix:
                return line
                
        return None
                
        
    def convert(self, additional_arguments = []):
        args = []
        map(lambda key: self._pair(args, key), self._options.keys())
        arguments = args + additional_arguments
        logging.debug(" ".join(arguments))
        (stdin, stdout) = self.execute_cmd(arguments)
        output = stdout.read()
        
        # split output to lines and check every line for error message
        error = self.handle_errors(output)
        if error != None:
            raise ValueError, "Can't convert video. Reason: %s" % error

        return output
        
    def unregister(self):
        args = ['-u']
        self._pair(args, name = "q")

        (stdin, stdout) = self.execute_cmd(args)
        return stdout.read()
        
        
    def info(self):   
        args = []
        if self.get_option('i') == '' and  self.get_option('q') == '':
            raise ValueError, "You don't specified path to video or unique identifier"
        
        map(lambda key: self._pair(args, key), self._options.keys())        
        
        
        args = args + ['-j']
        logging.debug("INFO ABOUT VIDEO ARGUMENTS: %s" % " ".join(args))
        
        (stdin, stdout) = self.execute_cmd(args)

        data = stdout.read()
        
        # handle errors
        error = self.handle_errors(data)
        if error != None:
            raise ValueError, "Can't get info about video. Reason: %s" % error

        reply_pairs = [obj.split('=') for obj in data.split("\n") if obj != '']
        reply_dict = {}
        
        for item in reply_pairs:
            try:
                key, val = tuple(item)
                reply_dict[key.lower()] = val
            except ValueError:
                try:    
                    reply_dict[item[0]] = ''
                except TypeError:
                    pass
                    
        
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
