from urllib import response
import boto3
import requests
import json
from flask import Flask, request, jsonify
import time 
import threading
import queue
import uuid
import os
import sys

AUTO_SCALE_TIME=10

app = Flask(__name__)

work_queue = queue.Queue() 
# work_queue.put({'work_id' : 1, 'time': time.time(), 'work': "hello world", 'iterations' : 200})
completed_work = queue.Queue()

@app.route('/')
def hello():
     return 'Hello, World! from load balancer tst'

@app.route('/enqueue', methods=['PUT'])
def enqueue():
     print('Got enqueue',file=sys.stdout)
     iterations = int(request.args.get('iterations'))
     buffer = request.get_data()
     print(f'enqueue to endpoint. buffer= {buffer}, iter= {iterations}', file=sys.stdout)
     work_id = str(uuid.uuid4())
     new_work = {'work_id' :work_id, 'time': time.time(), 'buffer': buffer, 'iterations' : iterations}
     work_queue.put(new_work)
     print(f'{work_queue.qsize()=}',file=sys.stdout)
     return {'work_id': work_id}

@app.route('/pullCompleted', methods=['POST'])
def pullCompleted():
    top = int(request.args.get('top'))
    # print(f'{top=}')
    completed_jobs = {}
    for i in range(top):
        try:
            completed_jobs[i]=completed_work.get_nowait()
        except queue.Empty:
            break
        # if completed_work.empty():
        #     break
        # completed_jobs.append(completed_work.get())
    print(f'{completed_work.qsize()=}',file=sys.stdout)
    return completed_jobs
#     return json.dumps(completed_jobs, indent=2)

@app.route('/get_work')
def get_work():
     print('Get work',file=sys.stdout)
     try:
          print(f'{work_queue.qsize()=}',file=sys.stdout)
          return work_queue.get_nowait()
     except queue.Empty:
          return 'queue is empty'
    # if work_queue.empty():
    #     return None
    # else:
    #     return work_queue.get()

@app.route('/send_completed_work', methods=['PUT'])
def send_completed_work():
    comp_work = request.get_data()
    completed_work.put({'work':str(comp_work),'work_id': request.args.get('id')})
    print(f'{completed_work.qsize()=}',file=sys.stdout)
    return "work submitted"

loadbalancer_ip = requests.get("http://169.254.169.254/latest/meta-data/local-ipv4").text
loadbalancer_sec_grp = requests.get("http://169.254.169.254/latest/meta-data/security-groups").text

def spawn_worker():
     ec2 = boto3.resource('ec2', region_name='us-east-1')
     user_data = f'''#!/bin/bash
cat > /home/ubuntu/app.py<< EOF
import requests
import os
import time
import sys
def work(buffer, iterations): 
     import hashlib 
     output = hashlib.sha512(buffer).digest() 
     for i in range(iterations - 1): 
          output = hashlib.sha512(output).digest() 
     return output

SECONDS_TO_TERMINATE = 5
last_worked_time = time.time()  

while True:
     response = requests.get("http://{loadbalancer_ip}:5000/get_work")
     print('response ' + response.text,file=sys.stdout)
     if response.text == 'queue is empty':
          if int(time.time() - last_worked_time) > SECONDS_TO_TERMINATE:
               break
          else:
               time.sleep(1)
     else:
          buffer = response.json()["buffer"]
          work_id = response.json()["work_id"]
          iterations = int(response.json()["iterations"])
          completed_work = work(buffer.encode('utf-8'), iterations)
          response = requests.put(f"http://{loadbalancer_ip}:5000/send_completed_work?id={{work_id}}", data=completed_work)
          last_worked_time = time.time()
os.system('sudo shutdown -h now')
EOF

sudo apt update
cd /home/ubuntu/
python3 app.py &

'''
     print(f'Spawning worker',file=sys.stdout)
     instance = ec2.create_instances(ImageId='ami-042e8287309f5df03',
     MinCount=1, MaxCount=1, UserData=user_data,
     InstanceType='t2.micro', SecurityGroups=[loadbalancer_sec_grp], InstanceInitiatedShutdownBehavior = 'terminate')
#     instance = ec2.run_instances(ImageId='ami-042e8287309f5df03', 
#     MinCount=1, MaxCount=1, UserData=user_data, 
#     InstanceType='t2.micro', SecurityGroups=[loadbalancer_sec_grp], InstanceInitiatedShutdownBehavior = 'terminate')
     instance[0].wait_until_running()
     print(f'instance running',file=sys.stdout)


def load_balance():
     while True:
          # TODO should be thread safe
          works_to_do = work_queue.queue
          if len(works_to_do) > 0:
                    peak_work = works_to_do[0]
                    # print(f'{works_to_do[0]=},{works_to_do[-1]=}')
                    if int(time.time() - peak_work['time']) > AUTO_SCALE_TIME:
                         spawn_worker()
                         time.sleep(30)
          time.sleep(5)

if __name__ == "__main__":
     threading.Thread(target=load_balance).start()
     app.run(host='0.0.0.0', port=5000)

