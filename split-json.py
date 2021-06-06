import hashlib
import json
import os
import sys

file = sys.argv[1]
split_num = int((os.path.getsize(file) / 1024 ** 2) / 100 + 1)
out_dir = os.path.dirname(file)
data_split = {}

with open(file) as f:
    data = json.load(f)


def key_to_bucket(k):
    return hex(int(hashlib.sha256(k.encode()).hexdigest(), 16) % split_num)[2:]


def dict_for_key(k):
    bucket = key_to_bucket(k)
    if bucket not in data_split:
        data_split[bucket] = dict(packages={})
        for key, val in data.items():
            if key != 'packages':
                data_split[bucket][key] = val
    return data_split[bucket]


for pname, pdata in data['packages'].items():
    dict_for_key(pname)['packages'][pname] = pdata


for bucket, data in data_split.items():
    with open(f"{file.rpartition('.json')[0]}.{bucket}.json", 'w') as f:
        json.dump(data, f, indent=2)

os.remove(file)
