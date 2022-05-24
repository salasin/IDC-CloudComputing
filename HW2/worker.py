import redis
import sys
import json
import hashlib

WORK_QUEUE = 'queue:work'
COMPLETED_WORK_QUEUE = 'queue:completed-work'
REDIS_PORT = 6379


def process(payload, iterations):
    output = hashlib.sha512(payload).digest()
    for i in range(iterations - 1):
        output = hashlib.sha512(output).digest()
    return output


redis_server_ip = sys.argv[1]
redis_conn = redis.Redis(host=redis_server_ip, port=REDIS_PORT, db=0)

value = True
while value:
    work = redis_conn.lpop(WORK_QUEUE)
    if work is not None:
        parsed_work = json.loads(work)
        work_id = parsed_work['work_id']
        iterations = parsed_work['iterations']
        payload = parsed_work['payload']
        processed_payload = process(bytes(payload, 'utf-8'), iterations)
        print(processed_payload)
        redis_conn.rpush(COMPLETED_WORK_QUEUE, json.dumps({'work_id': work_id, 'processed_payload': str(processed_payload)}))


