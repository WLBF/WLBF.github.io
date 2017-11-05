---
title: 第一次实习
date: 2016-01-21
tag: 日常
---
去公司实习了两天，在后端team，后端主要使用CoffeeScript来编写。抽空写了个统计自己已经写了多少代码的脚本，关键部分在于遍历文件夹和和正则表达式匹配文件。将空行、注释都过滤掉了。不知不觉已经有6w多行了。
``` python
import os
import re
import sys
LINES = 0
types = ["py", "scm", "cpp", "c"]
def valid(line):
        global parts
        if re.match(r"^[\s]*$|^\s*[/\*#]", line)!=None:
                return False
        return True
def countLines(location):
        global LINES
        f = open(location)
        for line in f:
                #print line
                if valid(line):
                        LINES += 1
                        #sys.stdout.write(line)
        f.close()
def counter(rootDir):
        global types
        temp = os.walk(rootDir)
        for root, dirs, files in temp:
                for f in files:
                        matchObj = re.match(r".*\.(.*)", f)
                        if matchObj != None and (matchObj.groups()[0] in types):
                                #print os.path.join(root, f)
                                countLines(os.path.join(root, f))
                                
if __name__ == "__main__":
        rootDir = raw_input("Root:")
        counter(rootDir)
        print "LinesNum:",LINES
```