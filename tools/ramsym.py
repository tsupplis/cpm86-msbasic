import re,sys
import os
bld=os.environ.get('BLD','build/dos')
m=open(bld+'/mbasic.map').read().replace('\r','')
S={}
for l in m.split('\n'):
    mm=re.match(r'\s*([0-9A-F]{4}):([0-9A-F]{4})\s+(?:Abs\s+)?(\S+)',l)
    if mm: S[mm.group(3)]=(int(mm.group(1),16),int(mm.group(2),16))
d=open(sys.argv[1],'rb').read()  # usage: ramsym.py ram.bin SYMBOL[:bytes] ...
cs=0x97
csend=S['MAPCLC'][1]
ds=cs+(csend+15)//16
print('CSEND',hex(csend),'DS',hex(ds))
def at(n,l):
    o=ds*16+S[n][1]; return d[o:o+l]
for a in sys.argv[2:]:
    n,_,l=a.partition(':'); l=int(l or 2)
    b=at(n,l); print('%-8s %04X: %s'%(n,S[n][1],b.hex(' ')))
