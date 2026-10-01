"""Small client for an already-running, authorized local ADB server.

Useful in restricted workspaces where adb.exe cannot write its user directory.
Never starts a server, changes USB authorization, or copies private ADB keys.
"""
import argparse
import socket
import struct
import time
from pathlib import Path

def exact(s, count):
    data = bytearray()
    while len(data) < count:
        part = s.recv(count-len(data))
        if not part: raise EOFError('ADB connection closed')
        data.extend(part)
    return bytes(data)

def request(s, text):
    payload = text.encode()
    s.sendall(f'{len(payload):04x}'.encode()+payload)
    if exact(s,4) != b'OKAY':
        raise RuntimeError(exact(s,int(exact(s,4),16)).decode(errors='replace'))

def connect(serial=None):
    s = socket.create_connection(('127.0.0.1',5037),5)
    s.settimeout(600)
    if serial: request(s,'host:transport:'+serial)
    return s

def devices():
    with connect() as s:
        request(s,'host:devices-l')
        return exact(s,int(exact(s,4),16)).decode()

def shell(serial, command):
    with connect(serial) as s:
        request(s,'shell:'+command)
        data=bytearray()
        while part:=s.recv(65536): data.extend(part)
        return data.decode(errors='replace')

def push(serial, source, destination):
    with connect(serial) as s, open(source,'rb') as f:
        request(s,'sync:')
        name=(destination+',33206').encode()
        s.sendall(b'SEND'+struct.pack('<I',len(name))+name)
        while part:=f.read(65536): s.sendall(b'DATA'+struct.pack('<I',len(part))+part)
        s.sendall(b'DONE'+struct.pack('<I',int(time.time())))
        status=exact(s,4);size=struct.unpack('<I',exact(s,4))[0]
        if status!=b'OKAY': raise RuntimeError(exact(s,size).decode(errors='replace'))

if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('command',choices=['devices','shell','push'])
    parser.add_argument('args',nargs='*')
    parser.add_argument('--serial')
    a=parser.parse_args()
    if a.command!='devices' and a.serial is None:
        connected=[line.split()[0] for line in devices().splitlines() if len(line.split())>1 and line.split()[1]=='device']
        if len(connected)!=1: parser.error('Select an authorized device with --serial')
        a.serial=connected[0]
    if a.command=='devices': print(devices())
    elif a.command=='shell': print(shell(a.serial,a.args[0]))
    else:
        push(a.serial,*a.args)
        print('Pushed',Path(a.args[0]).name)
