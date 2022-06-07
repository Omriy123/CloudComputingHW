from flask import Flask, request
import requests
import os
import sys

# config = {
#     "DEBUG": True  # run app in debug mode
# }

loadbalancer_ip = os.getenv('LOADBALANCER_IP')

app = Flask(__name__)
# app.config.from_mapping(config)

@app.route('/')
def hello():
     return 'Hello, World! from endpoint ' + str(loadbalancer_ip)

@app.route('/enqueue', methods=['PUT'])
def enqueue():
    iterations = request.args.get('iterations')
    work = request.get_data()
    print(f'enqueue to load balancer ip= {loadbalancer_ip}. work= {work}, iter= {iterations}', file=sys.stdout)
    # print(f"http://{loadbalancer_ip}:5000/enqueue?iterations={iterations}",file=sys.stdout)
    response = requests.put(f"http://{loadbalancer_ip}:5000/enqueue?iterations={iterations}", data=work)
    return response.content

@app.route('/pullCompleted', methods=['POST'])
def pullCompleted():
    top = request.args.get('top')
    print(f'pull completed from load balancer. top= {top}', file=sys.stdout)
    response = requests.post(f"http://{loadbalancer_ip}:5000/pullCompleted?top={top}")
    return response.content


