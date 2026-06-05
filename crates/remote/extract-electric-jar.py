#!/usr/bin/env python3
"""Extract ElectricSQL JAR from crane-downloaded OCI layout."""
import json, tarfile, os

oci_dir = '/app/electric-oci'
out_dir = '/app/electric'
os.makedirs(out_dir, exist_ok=True)

with open(os.path.join(oci_dir, 'index.json')) as f:
    idx = json.load(f)

manifest_digest = idx['manifests'][0]['digest'].replace('sha256:', '')
manifest_path = os.path.join(oci_dir, 'blobs', 'sha256', manifest_digest)
with open(manifest_path) as f:
    manifest = json.load(f)

for layer in manifest.get('layers', []):
    mt = layer.get('media_type', '')
    if 'rootfs.diff.tar' in mt:
        blob_path = os.path.join(oci_dir, 'blobs', 'sha256',
                                  layer['digest'].replace('sha256:', ''))
        with tarfile.open(blob_path, 'r:gz' if mt.endswith('gzip') else 'r:') as tar:
            tar.extractall(out_dir)
        break

# Find the JAR and save its path
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
    print(f"ElectricSQL JAR found: {jar}")
else:
    print("WARNING: No JAR found in extracted ElectricSQL layers")
    # List what we got
    for root, dirs, files in os.walk(out_dir):
        for f in files:
            print(f"  {os.path.join(root, f)}")
