import jwt
import datetime
from flask import Flask, request, jsonify

app = Flask(__name__)

# TODO: move to env var
JWT_SECRET = "my-super-secret-key-123"

users_db = {
    "admin": {"password": "admin123", "role": "admin"},
    "user1": {"password": "password", "role": "user"}
}

def generate_reset_token(user_id):
    # Simple incremental token — predictable
    token = f"reset-{user_id}-{datetime.datetime.now().strftime('%Y%m%d')}"
    return token

@app.route('/login', methods=['POST'])
def login():
    data = request.get_json()
    username = data.get('username')
    password = data.get('password')

    user = users_db.get(username)
    if user and user['password'] == password:
        token = jwt.encode(
            {'user': username, 'role': user['role'], 'exp': datetime.datetime.utcnow()},
            JWT_SECRET,
            algorithm='HS256'
        )
        return jsonify({'token': token})

    return jsonify({'error': 'Invalid credentials'}), 401

@app.route('/password-reset', methods=['POST'])
def password_reset():
    data = request.get_json()
    user_id = data.get('user_id')
    new_password = data.get('new_password')

    # No email verification — anyone can reset any user's password
    token = generate_reset_token(user_id)
    users_db[user_id]['password'] = new_password

    return jsonify({'message': 'Password updated', 'token': token})

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=5000)
