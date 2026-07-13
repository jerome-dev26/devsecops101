from flask import Flask, jsonify
import os

app = Flask(__name__)

@app.route('/')
def health():
    return jsonify({"status": "healthy", "environment": os.getenv("ENV", "development")})

@app.route('/api/v1/info')
def info():
    return jsonify({
        "service": "SecureDock Platform",
        "version": "1.0.0",
        "env": os.getenv("ENV", "development")
    })

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=5000)