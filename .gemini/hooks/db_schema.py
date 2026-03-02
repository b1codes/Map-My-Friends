import subprocess
import json

def get_db_schema():
    try:
        # Check if container is running
        res = subprocess.run(['docker', 'compose', 'ps', 'api', '--format', '{{.State}}'], capture_output=True, text=True)
        if 'running' not in res.stdout:
            return "Database service not running."
        
        # Run inspectdb
        res = subprocess.run(['docker', 'compose', 'exec', '-T', 'api', 'poetry', 'run', 'python', 'manage.py', 'inspectdb'], capture_output=True, text=True)
        lines = []
        for line in res.stdout.split('
'):
            if line.startswith('class ') or 'location =' in line:
                lines.append(line.strip())
        return "
".join(lines)
    except Exception as e:
        return f"Error getting DB schema: {str(e)}"

print(json.dumps({"db_schema": get_db_schema()}))
