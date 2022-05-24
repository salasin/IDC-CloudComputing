from flask import Flask, Response, request
import json
import redis
import uuid
import re
import sys
from apscheduler.schedulers.background import BackgroundScheduler
import boto3

WORK_QUEUE = 'queue:work'
COMPLETED_WORK_QUEUE = 'queue:completed-work'
REDIS_PORT = 6379

app = Flask(__name__)


def get_redis_conn(redis_server_ip):
    return redis.Redis(host=redis_server_ip, port=REDIS_PORT, db=0)


@app.route('/enqueue', methods=['PUT'])
def execute_enqueue():
    work_id = str(uuid.uuid1())
    iterations_arg = request.args.get('iterations')
    iterations = int(re.findall('\d+', iterations_arg)[0])
    file = request.files['file']
    file_content = file.read()
    redis_conn = get_redis_conn(app.config.get('redis_server_ip'))
    redis_conn.rpush(WORK_QUEUE, json.dumps({'work_id': work_id, 'iterations': iterations, 'payload': str(file_content)}))
    return Response(mimetype='application/json',
                    response=json.dumps({'work_id': work_id}),
                    status=200)


@app.route('/pullCompleted', methods=['POST'])
def execute_pull_completed():
    top_arg = request.args.get('top')
    top = int(re.findall('\d+', top_arg)[0])
    redis_conn = get_redis_conn(app.config.get('redis_server_ip'))
    # TODO: change this to be atomic
    completed_work = []
    for i in range(top):
        item = redis_conn.lpop(COMPLETED_WORK_QUEUE)
        if item is not None:
            completed_work.append(json.loads(item))
    if len(completed_work) == 0:
        return Response(mimetype='application/json',
                        response='Work completed queue is empty.',
                        status=200)
    return Response(mimetype='application/json',
                    response=json.dumps({'completed_work': completed_work}),
                    status=200)


def report_work_queue_len(redis_server_ip, aws_access_key_id, aws_secret_access_key):
    redis_conn = get_redis_conn(redis_server_ip)
    cloud_watch = boto3.client('cloudwatch', region_name='us-east-1', aws_access_key_id=aws_access_key_id, aws_secret_access_key=aws_secret_access_key)
    cloud_watch.put_metric_data(
        MetricData=[
            {
                'MetricName': 'work_queue_length',
                'Unit': 'Count',
                'Value': redis_conn.llen(WORK_QUEUE)
            },
        ],
        Namespace='CloudComputingHW2'
    )


if __name__ == '__main__':
    redis_server_ip = sys.argv[1]
    is_primary = sys.argv[2] == 'primary'
    aws_access_key_id = sys.argv[3]
    aws_secret_access_key = sys.argv[4]
    if is_primary:
        scheduler = BackgroundScheduler()
        scheduler.add_job(func=report_work_queue_len, args=[redis_server_ip, aws_access_key_id, aws_secret_access_key], trigger="interval", seconds=60)
        scheduler.start()
    app.config['redis_server_ip'] = redis_server_ip
    app.run(host="0.0.0.0")
