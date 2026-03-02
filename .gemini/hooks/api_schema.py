import os
import glob
import json

def get_urls():
    urls = []
    files = glob.glob('backend/apps/*/urls.py')
    for f in files:
        with open(f, 'r') as file:
            for line in file:
                if 'path(' in line:
                    urls.append(f"{f}: {line.strip()}")
    return "
".join(urls)

print(json.dumps({"api_schema": get_urls()}))
