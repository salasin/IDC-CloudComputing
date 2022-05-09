import redis

print('Hello')
conn = redis.Redis(host='34.201.134.71', port=6379, db=0)
le = conn.llen('queue:work')
print(le)
conn.rpush('queue:work', 'id:1')
le = conn.llen('queue:work')
print(le)
print('World')
