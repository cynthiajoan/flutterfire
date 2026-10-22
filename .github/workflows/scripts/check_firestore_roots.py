#!/usr/bin/env python3
"""omg/105320: verify the Firestore gRPC root bundle linked into a built app.

Usage: check_firestore_roots.py <binary-or-dir> [<binary-or-dir> ...]

For every Mach-O under the given paths that embeds PEM blocks, extract the
bundle, compare it (by SHA-256 of each DER cert) with the pre-fix (13.0.1 /
12.19.0) and post-fix (main, PR #16930) bundles from firebase-ios-sdk, then run
`openssl verify` with the system store disabled against the 14 attack chains
published at emudhra.we-have-a-problem.com. Exits non-zero unless at least one
binary matches the post-fix bundle exactly and rejects all 14 chains.
"""
import base64
import hashlib
import io
import os
import re
import subprocess
import sys
import tempfile
import urllib.request
import zipfile

BEGIN = b"-----BEGIN CERTIFICATE-----"
END = b"-----END CERTIFICATE-----"
COMPROMISED = ["emSign ECC Root CA - G3", "AAA Certificate Services"]
RAW = "https://raw.githubusercontent.com/firebase/firebase-ios-sdk/{}/Firestore/core/src/remote/grpc_root_certificates_generated.cc"
CHAINS = "https://emudhra.we-have-a-problem.com/chains.zip"
MAGICS = (b"\xca\xfe\xba\xbe", b"\xcf\xfa\xed\xfe", b"\xce\xfa\xed\xfe", b"\xfe\xed\xfa\xcf", b"\xfe\xed\xfa\xce", b"!<ar")


def fetch(url):
    with urllib.request.urlopen(url, timeout=60) as r:
        return r.read()


def pem_from_cc(txt):
    body = txt.split("= {", 1)[1].split("};", 1)[0]
    return bytes(int(h, 16) for h in re.findall(r"0x([0-9a-fA-F]{2})", body)).rstrip(b"\x00")


def certs(blob):
    out, pos = [], 0
    while True:
        s = blob.find(BEGIN, pos)
        if s < 0:
            return out
        e = blob.find(END, s)
        if e < 0:
            return out
        pem = blob[s : e + len(END)]
        try:
            der = base64.b64decode(b"".join(pem[len(BEGIN) : -len(END)].split()), validate=True)
            out.append((pem, der))
        except Exception:
            pass
        pos = e + len(END)


def subject(der):
    r = subprocess.run(["openssl", "x509", "-inform", "DER", "-noout", "-subject", "-nameopt", "RFC2253"], input=der, capture_output=True)
    return r.stdout.decode().strip()


def fps(cs):
    return {hashlib.sha256(d).hexdigest() for _, d in cs}


def is_macho(p):
    try:
        with open(p, "rb") as f:
            return f.read(4) in MAGICS
    except OSError:
        return False


def verify_chains(bundle_pem, chains_dir):
    accepted = []
    for name in sorted(os.listdir(chains_dir)):
        if not name.endswith(".pem"):
            continue
        blocks = re.findall(rb"-----BEGIN CERTIFICATE-----.*?-----END CERTIFICATE-----", open(os.path.join(chains_dir, name), "rb").read(), re.S)
        with tempfile.NamedTemporaryFile(delete=False) as leaf, tempfile.NamedTemporaryFile(delete=False) as inter, tempfile.NamedTemporaryFile(delete=False) as ca:
            leaf.write(blocks[0])
            inter.write(b"\n".join(blocks[1:]))
            ca.write(bundle_pem)
        r = subprocess.run(["openssl", "verify", "-no-CApath", "-no-CAstore", "-CAfile", ca.name, "-untrusted", inter.name, leaf.name], capture_output=True)
        if r.returncode == 0:
            accepted.append(name)
    return accepted


def main():
    old = certs(pem_from_cc(fetch(RAW.format("13.0.1")).decode()))
    new = certs(pem_from_cc(fetch(RAW.format("main")).decode()))
    print(f"reference bundles: pre-fix={len(old)} certs, post-fix={len(new)} certs")
    chains_dir = tempfile.mkdtemp()
    zipfile.ZipFile(io.BytesIO(fetch(CHAINS))).extractall(chains_dir)
    chains_dir = os.path.join(chains_dir, "chains")
    n_chains = len([f for f in os.listdir(chains_dir) if f.endswith(".pem")])
    old_pem = b"\n".join(p for p, _ in old)
    ctrl = verify_chains(old_pem, chains_dir)
    print(f"positive control: pre-fix bundle accepts {len(ctrl)}/{n_chains} attack chains")

    good = 0
    for root in sys.argv[1:]:
        paths = [root] if os.path.isfile(root) else [os.path.join(dp, f) for dp, _, fn in os.walk(root) for f in fn]
        for p in paths:
            if not is_macho(p):
                continue
            blob = open(p, "rb").read()
            cs = certs(blob)
            if not cs:
                continue
            f = fps(cs)
            names = [c for c in COMPROMISED if c.encode() in blob]
            accepted = verify_chains(b"\n".join(x for x, _ in cs), chains_dir)
            if f == fps(new):
                verdict = "MATCHES post-fix bundle"
            elif f == fps(old):
                verdict = "MATCHES PRE-FIX bundle (VULNERABLE)"
            else:
                verdict = f"bundle differs ({len(f)} certs; {len(f & fps(new))} in post-fix, {len(f & fps(old))} in pre-fix)"
            ok = f == fps(new) and not names and not accepted
            good += ok
            print(f"{'PASS' if ok else 'FAIL'} {p}\n     {len(cs)} PEM certs; {verdict}; compromised root names present: {names or 'none'}; attack chains accepted: {len(accepted)}/{n_chains}")
            for a in accepted:
                print("       accepted:", a)
    if good == 0:
        print("::error::no binary carrying the fixed Firestore root bundle was found")
        sys.exit(1)
    print(f"OK: {good} binary(ies) carry the fixed bundle and reject all attack chains")


if __name__ == "__main__":
    main()
