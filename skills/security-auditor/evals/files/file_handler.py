import os
import urllib.request
from flask import Flask, request, send_from_directory

app = Flask(__name__)
UPLOAD_DIR = "/var/www/uploads"

@app.route('/upload', methods=['POST'])
def upload_file():
    """Handle file uploads from users."""
    file = request.files['document']
    filename = file.filename
    
    # Save directly to disk without validation
    filepath = os.path.join(UPLOAD_DIR, filename)
    file.save(filepath)
    
    return {"status": "uploaded", "path": filepath}

@app.route('/fetch', methods=['POST'])
def fetch_remote():
    """Fetch remote resource by URL."""
    url = request.json.get('url')
    
    # No URL validation - user can request internal resources
    response = urllib.request.urlopen(url)
    data = response.read()
    
    return {"content": data.decode('utf-8')}

@app.route('/download/<path:filename>')
def download(filename):
    """Download uploaded files."""
    return send_from_directory(UPLOAD_DIR, filename)

if __name__ == '__main__':
    app.run(debug=True)
