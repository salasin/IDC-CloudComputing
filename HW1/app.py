from flask import Flask, Response, request
import json
import sqlite3
from time import time
import uuid

app = Flask(__name__)
conn = sqlite3.connect(r'entries.db')
cur = conn.cursor()
cur.execute('CREATE TABLE IF NOT EXISTS entries (plate TEXT UNIQUE, ticket_id TEXT, parking_lot TEXT, entry_timestamp TEXT);')


@app.route('/entry', methods=['POST'])
def execute_entry():
    entry_timestamp = int(time())
    ticket_id = str(uuid.uuid1())
    plate = request.args.get('plate')
    parking_lot = request.args.get('parkingLot')
    conn = sqlite3.connect(r'entries.db')
    cur = conn.cursor()
    cur.execute('INSERT INTO entries (plate, ticket_id, parking_lot, entry_timestamp) VALUES (?, ? ,? ,?)', (plate, ticket_id, parking_lot, entry_timestamp))
    conn.commit()
    return Response(mimetype='application/json',
                    response=json.dumps({'ticket_id': ticket_id}),
                    status=200)


@app.route('/exit', methods=['POST'])
def execute_exit():
    exit_timestamp = int(time())
    ticket_id = request.args.get('ticketId')
    conn = sqlite3.connect(r'entries.db')
    cur = conn.cursor()
    cur.execute("SELECT plate, parking_lot, entry_timestamp FROM entries WHERE ticket_id = ?", (ticket_id,))
    rows = cur.fetchall()
    row = rows[0]
    cur.execute("DELETE FROM entries WHERE ticket_id = ?", (ticket_id,))
    conn.commit()
    entry_timestamp = int(row[2])
    total_parked_time_minutes = int((exit_timestamp - entry_timestamp) / 60)
    # The price is 10$ per hour, we charge in 15 minutes increments and round to the bottom.
    charge = int(total_parked_time_minutes / 15) * 2.5
    return Response(mimetype='application/json',
                    response=json.dumps({'plate': row[0], 'total_parked_time_minutes': total_parked_time_minutes, 'parking_lot': row[1], 'charge': charge}),
                    status=200)

