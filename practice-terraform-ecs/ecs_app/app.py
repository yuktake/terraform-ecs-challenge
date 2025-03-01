#!/usr/bin/env python3

from flask import Flask, request, jsonify
import os
import requests
import mysql.connector

app = Flask(__name__)

# MySQLの接続設定
db_config = {
    "host": os.environ["HOST"],  # MySQLサーバーのホスト名
    "user": os.environ["DB_USER"],  # MySQLのユーザー名
    "password": os.environ["DB_PASSWORD"],  # MySQLのパスワード
    "database": os.environ["DB_NAME"],  # 接続するデータベース名
}

# ヘルスチェックに応答するためのエンドポイント
@app.route("/health")
def health():
    return "OK", 200

# 回答を受け取るエンドポイント
@app.route("/q")
def q():
    # リクエストパラメータの"a"から回答を取得
    answer_input = request.args.get("a")
    if not answer_input:
        return "No message provided", 400
    try:
        if answer_input == os.environ["CORRECT_ANSWER"]:
            return "Correct", 200
        else:
            return "Incorrect", 400
    except Exception:
        return "Error", 500
    
@app.route("/call_api")
def call_api():
    url = "https://jsonplaceholder.typicode.com/todos/1"
    try:
        response = requests.get(url)
        if response.status_code == 200:
            return response.json(), 200
        else:
            return "Error", 500
    except Exception:
        return "Error", 500

@app.route("/data")
def get_data():
    try:
        # MySQLに接続
        conn = mysql.connector.connect(**db_config)
        cursor = conn.cursor(dictionary=True)  # 結果を辞書形式で取得

        # SQLクエリの実行
        cursor.execute("SELECT * FROM users")  # users テーブルからデータ取得
        results = cursor.fetchall()  # すべてのデータを取得

        # 接続を閉じる
        cursor.close()
        conn.close()

        # JSONで返す
        return jsonify(results)

    except mysql.connector.Error as err:
        return jsonify({"error": str(err)}), 500
    
if __name__ == "__main__":
    app.run(host="0.0.0.0", port=5000)