#!/usr/bin/env python3
"""Extract ElectricSQL JAR from skopeo-downloaded OCI layout."""
import json, tarfile, os, sys, shutil

oci_dir = '/tmp/electric-oci'
out_dir = '/tmp/electric-out'
os.makedirs(out_dir, exist_ok=True)

idx_path = os.path.join(oci_dir, 'index.json')
with open(idx_path) as f:
    idx = json.load(f)

manifest_digest = idx['manifests'][0]['digest'].replace('sha256:', '')

manifest_path = os.path.join(oci_dir, 'blobs', 'sha256', manifest_digest)
if not os.path.isfile(manifest_path):
    manifest_path = os.path.join(oci_dir, manifest_digest)
with open(manifest_path) as f:
    manifest = json.load(f)

for layer in manifest.get('layers', []):
    mt = layer.get('media_type', '')
    digest = layer.get('digest', '').replace('sha256:', '')
    blob_path = os.path.join(oci_dir, 'blobs', 'sha256', digest)
    if not os.path.isfile(blob_path):
        blob_path = os.path.join(oci_dir, digest)
    if not os.path.isfile(blob_path):
        continue
    mode = 'r:gz' if 'gzip' in mt or 'gz' in mt else 'r:'
    with tarfile.open(blob_path, mode) as tar:
        tar.extractall(out_dir)

jar = None
for root, dirs, files in os.walk(out_dir):
    for f in files:
        if f.endswith('.jar'):
            jar = os.path.join(root, f)
            break
    if jar:
        break

if not jar:
    print('ERROR: No JAR found')
    sys.exit(1)

os.makedirs('/opt/electric', exist_ok=True)
shutil.copy2(jar, '/opt/electric/electric.jar')
with open('/opt/electric/jar-path.txt', 'w') as f:
    f.write('/opt/electric/electric.jar')
print(f'JAR extracted to /opt/electric/electric.jar')
