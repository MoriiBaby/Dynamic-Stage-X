#!/usr/bin/env python3
"""Initial native package inventory, no execution or installation of package contents."""
import gzip,hashlib,io,json,lzma,pathlib,plistlib,subprocess,sys,tarfile
folder=pathlib.Path(sys.argv[1]); output=pathlib.Path(sys.argv[2])
files=list(folder.glob('*.deb')); assert len(files)==1,files
package=files[0]; raw=package.read_bytes(); assert raw[:8]==b'!<arch>\n'
offset=8; parts={}
while offset<len(raw):
    h=raw[offset:offset+60]; assert len(h)==60 and h[58:60]==b'`\n'
    name=h[:16].decode().strip().rstrip('/'); size=int(h[48:58]); assert name not in parts
    parts[name]=raw[offset+60:offset+60+size]; offset+=60+size+(size%2)
assert parts['debian-binary']==b'2.0\n'
def unpack(prefix):
    matches=[k for k in parts if k.startswith(prefix+'.tar')]; assert len(matches)==1
    name=matches[0]; data=parts[name]
    if name.endswith(('.xz','.lzma')): data=lzma.decompress(data,memlimit=192*1024*1024)
    elif name.endswith('.gz'): data=gzip.decompress(data)
    elif name.endswith('.zst'): data=subprocess.run(['zstd','-d','-c'],input=data,capture_output=True,check=True).stdout
    result={}
    with tarfile.open(fileobj=io.BytesIO(data)) as archive:
        for m in archive:
            p=pathlib.PurePosixPath(m.name); assert not p.is_absolute() and '..' not in p.parts
            assert m.uid == 0 and m.gid == 0, ('non-root numeric owner', m.name, m.uid, m.gid)
            if m.isdir(): continue
            key=p.as_posix().removeprefix('./'); assert key not in result
            assert m.isfile(),(key,m.type)
            result[key]=archive.extractfile(m).read()
    return result
control=unpack('control'); payload=unpack('data'); fields={}
for line in control['control'].decode().splitlines():
    if not line or line[0].isspace(): continue
    key,value=line.split(':',1); key=key.lower(); assert key not in fields,key; fields[key]=value.strip()
assert fields['package']=='com.tsangbaby.dynamicstagex'
assert fields['version']=='0.1.0~alpha4'
assert fields['architecture']=='iphoneos-arm64e'
assert 'firmware (>= 15.0)' in fields['depends'] and 'rootless-compat' not in fields.get('pre-depends','')
assert 'roothide' in [p.strip().split()[0] for p in fields['depends'].split(',')]
assert all(not p.startswith(('var/jb/','var/mobile/Library/pkgmirror/')) for p in payload)
assert any(p.endswith('/DynamicStageX.dylib') for p in payload)
assert any(p.endswith('/DynamicStageXPrefs.bundle/DynamicStageXPrefs') for p in payload)
assert all(not p.endswith(('.mp4','.zip','.py','.swift','.h','.c','.m')) for p in payload)
for name,data in payload.items():
    if name.endswith('.plist'): plistlib.loads(data)
report={'package':package.name,'bytes':len(raw),'sha256':hashlib.sha256(raw).hexdigest(),
 'control':fields,'files':[{'path':name,'bytes':len(data),'sha256':hashlib.sha256(data).hexdigest()} for name,data in sorted(payload.items())],
 'scope':'package identity/inventory only; full Mach-O/signature verification follows independently'}
output.write_text(json.dumps(report,indent=2)+'\n'); print(json.dumps(report,indent=2))
