# REDIS_SERVER_IP should be prepended here.

apt-get update
apt-get install -y python3-pip
apt-get install -y git-all
pip3 install redis
git clone "https://github.com/salasin/IDC-CloudComputing"
python3 IDC-CloudComputing/HW2/worker.py $REDIS_SERVER_IP
