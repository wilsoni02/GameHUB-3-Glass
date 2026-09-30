#!/usr/bin/env python3
"""Source-based InputText command-boundary check; not native UI certification.

Models Rainmeter Library/CommandHandler.cpp's outer bracket/triple-quote scan.
The only completed command must be a fixed callback with a numeric serial.
User input is read from InputText's string value, never from a Lua argument.
Python is a maintainer tool only.
"""
from pathlib import Path
import configparser
import random
import re

root=Path(__file__).resolve().parents[1]
hub=(root/'@Resources/Scripts/Hub.lua').read_text(encoding='utf-8')
ini=configparser.RawConfigParser(interpolation=None,strict=True)
ini.read(root/'Main/Main.ini',encoding='utf-8-sig')
assert ini['SearchInput']['Plugin']=='InputText'
assert ini['SearchInput']['FocusDismiss']=='1' and 'TopMost' not in ini['SearchInput']
assert ini['SearchText']['MeasureName']=='SearchInput'
assert "opt('SearchText','Text',discover.query~='' and '%1'" in hub
assert "local value=input and input:GetStringValue() or ''" in hub
assert "opt('SearchInput','DefaultValue','')" in hub
limit=int(re.search(r'local MAX_QUERY=(\d+)',hub)[1])
factor=int(re.search(r"string.rep\('\[',MAX_QUERY\*(\d+)\+1\)",hub)[1])
assert limit==128 and factor>=8

def completed_commands(text):
    start=None;depth=0;commands=[];i=0
    while i<len(text):
        if text[i]=='[':
            if depth==0:start=i
            depth+=1
        elif text[i]==']':
            depth-=1
            if depth==0 and start is not None:
                commands.append(text[start+1:i].lstrip())
        elif text.startswith('"""',i):
            i+=3
            end=text.find('"""',i)
            if end>=0:i=end+2
        i+=1
    return commands

callback='!CommandMeasure Hub "SearchCommit(42)"'
prefix='['+callback+']'+'['*(limit*factor+1)
samples=["Tom Clancy's",'100% [Gold]','"Ghost"','Pokémon Édition','Straße',
         '[&Hub:Close()]','#CURRENTCONFIG#','] [!Quit]',
         '""" ]]] """ [!Refresh]',"'\"\\",'', 'a=b;#c']
rng=random.Random(42)
alphabet='abc[]!&:#$()"\'\\ %é中'
for length in range(limit*factor+1):
    samples.extend([']'*length,'['*length,('"""[]'*length)[:length],
                    ''.join(rng.choice(alphabet) for _ in range(length))])
for sample in samples:
    assert len(sample)<=limit*factor
    assert completed_commands(prefix+sample)==[callback],repr(sample)
print('PASS: InputText bound measure, fixed callback, quotes/brackets/macros, and scaled input-limit boundary')
