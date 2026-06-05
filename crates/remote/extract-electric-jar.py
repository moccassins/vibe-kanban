#!/usr/bin/env python3
"""Extract ElectricSQL JAR from crane-downloaded OCI layout.

crane pull stores an OCI image layout:
  /app/electric-oci/
    index.json
    blobs/sha256/<digest>
    manifests/sha256/<digest>

The script parses the layout, finds the rootfs layer tarball,
extracts it, and locates the ElectricSQL JAR.
"""
import json, tarfile, os, sys

oci_dir = '/app/electric-oci'
out_dir = '/app/electric'
os.makedirs(out_dir, exist_ok=True)

# ── Verify OCI layout structure ──────────────────────────────────
if not os.path.isdir(oci_dir):
    print(f"FATAL: {oci_dir} is not a directory (got: {os.path.exists(oci_dir) and 'file' or 'missing'})")
    print("crane pull must output to a DIRECTORY path (no trailing slash needed).")
    sys.exit(1)

idx_path = os.path.join(oci_dir, 'index.json')
if not os.path.isfile(idx_path):
    print(f"FATAL: {idx_path} not found. OCI layout looks wrong.")
    # List what's in there for debugging
    for entry in os.listdir(oci_dir):
        full = os.path.join(oci_dir, entry)
        print(f"  {entry} -> {'dir' if os.path.isdir(full) else 'file'}")
    sys.exit(1)

# ── Parse index.json → find manifest ────────────────────────────
with open(idx_path) as f:
    idx = json.load(f)

manifests = idx.get('manifests', [])
if not manifests:
    print("FATAL: No manifests in index.json")
    sys.exit(1)

manifest_digest = manifests[0]['digest'].replace('sha256:', '')
manifest_path = os.path.join(oci_dir, 'blobs', 'sha256', manifest_digest)
if not os.path.isfile(manifest_path):
    # Try manifests/ dir instead of blobs/
    manifest_path = os.path.join(oci_dir, 'manifests', manifest_digest)
if not os.path.isfile(manifest_path):
    print(f"FATAL: manifest not found at blobs/sha256/{manifest_digest}")
    sys.exit(1)

with open(manifest_path) as f:
    manifest = json.load(f)

# ── Extract rootfs layers ───────────────────────────────────────
found = False
for layer in manifest.get('layers', []):
    mt = layer.get('media_type', '')
    digest = layer.get('digest', '').replace('sha256:', '')
    if 'tar' not in mt:
        continue
    blob_path = os.path.join(oci_dir, 'blobs', 'sha256', digest)
    if not os.path.isfile(blob_path):
        blob_path = os.path.join(oci_dir, 'blobs', digest)
    if not os.path.isfile(blob_path):
        print(f"  skip layer {digest[:16]}... (blob not found)")
        continue
    # Detect compression
    if mt.endswith('gzip') or mt.endswith('gz'):
        mode = 'r:gz'
    elif mt.endswith('zstd'):
        print("  skip zstd layer (not supported)")
        continue
    else:
        mode = 'r:'
    print(f"  extracting layer {digest[:16]}... ({mt})")
    with tarfile.open(blob_path, mode) as tar:
        tar.extractall(out_dir)
    found = True

if not found:
    print("FATAL: No extractable tar layers found")
    sys.exit(1)

# ── Locate the JAR ───────────────────────────────────────────────
jar = None
for root, dirs, files in os.walk(out_dir):
    for f in files:
        if f.endswith('.jar'):
            jar = os.path.join(root, f)
            break
    if jar:
        break

with open('/tmp/electric-jar-path.txt', 'w') as f:
    f.write(jar or '')

if jar:
    print(f"OK: ElectricSQL JAR: {jar}")
else:
    print("WARNING: No JAR found in extracted layers:")
    for root, dirs, files in os.walk(out_dir):
        for f in files:
            print(f"  {os.path.join(root, f)}")
    sys.exit(1)
