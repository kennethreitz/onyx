import json, hashlib
from cryptography.hazmat.primitives.kdf.hkdf import HKDF
from cryptography.hazmat.primitives import hashes
from cryptography.hazmat.primitives.ciphers.aead import AESSIV, AESGCM
v=json.load(open(__import__('sys').argv[1] if len(__import__('sys').argv)>1 else 'Tests/OnyxSyncTests/Resources/obsidian-sync-vectors.json'))
def hk(key,salt,info): return HKDF(hashes.SHA256(),32,salt,info).derive(key)
ok=bad=0
for c in v['cases']:
    k=hashlib.scrypt(c['password'].encode(),salt=c['salt'].encode(),n=32768,r=8,p=1,dklen=32,maxmem=2**26)
    import unicodedata
    k=hashlib.scrypt(unicodedata.normalize('NFKC',c['password']).encode(),salt=c['salt'].encode(),n=32768,r=8,p=1,dklen=32,maxmem=2**26)
    assert k.hex()==c['key'], 'scrypt'
    v3=c['versions']['3']; s=c['salt'].encode()
    assert hk(k,s,b'ObsidianKeyHash').hex()==v3['keyHash']
    siv=AESSIV(hk(k,s,b'ObsidianAesSivMac')+hk(k,s,b'ObsidianAesSivEnc'))
    for d in [x for x in v3['deterministic'] if x['plain']]:
        if siv.encrypt(d['plain'].encode(),None).hex()==d['cipher']: ok+=1
        else: bad+=1; print('mismatch',d['plain'][:30])
    g=hk(k,b'',b'ObsidianAesGcm'); assert g.hex()==v3['gcmKey']
    ct=v3['content']; assert (bytes.fromhex(ct['iv'])+AESGCM(g).encrypt(bytes.fromhex(ct['iv']),bytes.fromhex(ct['plainHex']),None)).hex()==ct['cipher']
    v0=c['versions']['0']; assert hashlib.sha256(k).hexdigest()==v0['keyHash']
    for d in v0['deterministic']:
        p=d['plain'].encode(); iv=hashlib.sha256(p).digest()[:12]
        assert (iv+AESGCM(k).encrypt(iv,p,None)).hex()==d['cipher']
w=v['ctrWrap']; c=v['cases'][0]; k=bytes.fromhex(c['key']); s=c['salt'].encode()
siv=AESSIV(hk(k,s,b'ObsidianAesSivMac')+hk(k,s,b'ObsidianAesSivEnc'))
print('siv ok',ok,'bad',bad,'; RFC5297 lib on wrap probe matches JS?', siv.encrypt(w['plain'].encode(),None).hex()==w['cipher'])
from cryptography.hazmat.primitives.ciphers import Cipher, algorithms, modes
ct=bytes.fromhex(w['cipher']); V=bytearray(ct[:16]); V[8]&=0x7f; V[12]&=0x7f
ek=Cipher(algorithms.AES(hk(k,s,b'ObsidianAesSivEnc')),modes.ECB()).encryptor()
pt=w['plain'].encode(); out=b''
for i in range(0,len(pt),16):
    blk=bytes(V[:14])+((int.from_bytes(V[14:],'big')+i//16)%65536).to_bytes(2,'big')
    out+=bytes(a^b for a,b in zip(pt[i:i+16],ek.update(blk)))
print('16-bit-wrap CTR reproduces JS:', out==ct[16:])
