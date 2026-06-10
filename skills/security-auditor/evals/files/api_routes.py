import sqlite3
from flask import Flask, request, jsonify, render_template_string

app = Flask(__name__)

def get_db():
    return sqlite3.connect('app.db')

@app.route('/user/search')
def search_user():
    name = request.args.get('name', '')
    conn = get_db()
    cursor = conn.cursor()

    # Vulnerable to SQL injection
    query = f"SELECT * FROM users WHERE name = '{name}'"
    cursor.execute(query)
    results = cursor.fetchall()

    return jsonify({'users': results})

@app.route('/user/profile/<int:user_id>')
def get_profile(user_id):
    conn = get_db()
    cursor = conn.cursor()

    # Also vulnerable — parameterized query exists but not used
    query = "SELECT * FROM users WHERE id = %s" % user_id
    cursor.execute(query)
    user = cursor.fetchone()

    # Log sensitive data
    app.logger.info(f"Fetched profile for user: {user}")

    return jsonify({'user': user})

@app.route('/admin/delete/<int:user_id>', methods=['POST'])
def delete_user(user_id):
    # No authorization check — any user can delete anyone
    conn = get_db()
    cursor = conn.cursor()
    cursor.execute("DELETE FROM users WHERE id = ?", (user_id,))
    conn.commit()

    return jsonify({'message': 'User deleted'})

@app.route('/greet')
def greet():
    name = request.args.get('name', 'Guest')
    # Reflected XSS
    template = f"<h1>Hello, {name}!</h1><p>Welcome to our site.</p>"
    return render_template_string(template)

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=5000)
