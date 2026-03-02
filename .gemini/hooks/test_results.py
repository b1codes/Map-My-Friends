import os
import json

def get_test_results():
    test_log = '.gemini/last_test_results.txt'
    if os.path.exists(test_log):
        with open(test_log, 'r') as f:
            return f.read()
    return "No test results available. Run 'make test' to generate them."

print(json.dumps({"test_results": get_test_results()}))
