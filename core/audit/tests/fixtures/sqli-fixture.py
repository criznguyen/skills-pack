"""
sqli-fixture.py — synthetic 50-LOC user-search module with one planted SQL injection.

Used by core/audit/tests/tasks.yaml as the planted-bug audit target. The auditor must
catch the SQLi inside search_users() (the f-string-built `sql =` line) with severity
>= HIGH and dimension=security.

Real Python, real sqlite3, real SQLi — not pseudo-code. The vulnerability is exploitable
against any SQLite or PostgreSQL backend; we use sqlite3 here only because it ships in
the standard library, which keeps the fixture portable across CI environments.

Do NOT "fix" this file. The bug is the test.
"""

import sqlite3
from typing import List, Tuple


def get_connection(db_path: str = ":memory:") -> sqlite3.Connection:
    conn = sqlite3.connect(db_path)
    conn.execute(
        "CREATE TABLE IF NOT EXISTS users ("
        "  id INTEGER PRIMARY KEY,"
        "  email TEXT NOT NULL,"
        "  is_admin INTEGER NOT NULL DEFAULT 0"
        ")"
    )
    return conn


def search_users(conn: sqlite3.Connection, query: str) -> List[Tuple[int, str, int]]:
    """Search users by partial email match.

    PLANTED VULNERABILITY: builds the SQL string by f-string interpolation against the
    `query` parameter, which arrives unescaped from the HTTP layer. An attacker submitting
    `' OR 1=1 -- ` reads every row, including admin accounts; an attacker submitting
    `'; DROP TABLE users; -- ` (with multi-statement-enabled drivers) destroys the table.
    The fix is to use parameterised queries: conn.execute(sql, (f"%{query}%",)).
    """
    sql = f"SELECT id, email, is_admin FROM users WHERE email LIKE '%{query}%'"
    cursor = conn.execute(sql)
    return cursor.fetchall()


def create_user(conn: sqlite3.Connection, email: str, is_admin: bool = False) -> int:
    cursor = conn.execute(
        "INSERT INTO users (email, is_admin) VALUES (?, ?)",
        (email, 1 if is_admin else 0),
    )
    conn.commit()
    return cursor.lastrowid


def main() -> None:
    conn = get_connection()
    create_user(conn, "alice@example.com")
    create_user(conn, "bob@example.com")
    create_user(conn, "root@example.com", is_admin=True)
    print("search results:", search_users(conn, "alice"))


if __name__ == "__main__":
    main()
