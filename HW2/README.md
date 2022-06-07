 
# Our solution
We create 2 endpoints and a load balancer. The endpoints have 2 HTTP routes, 'enqueue' and 'pullCompleted' it will send a HTTP request to the load balancer.

The load balancer will hold the work requests in a queue, it will also hold a queue of the completed works.

The load balancer have 4 HTTP routes, 'enqueue' and 'pullCompleted' that recieve from the endpoints and 'get_work' and 'send_completed_work' that will give work to the worker and recieve the completed work from it.

The script will create 2 security groups: 1st for the endpoints that will allow all inbound tcp:5000 requests, and 2nd for the load balancer and the workers that will allow tcp:5000 requests from ec2 instances that are associated to the load balancer security group and the endpoints security group.

It will create iam instance profile using the policy json files. The instance profile will allow the load balancer to launch the workers. 

We run the load balancer and the endpoints instances and deploy the .py files to them. We save in the endpoints the private ip of the load balancer.

# Expected failures and production considirations

1.	The queues inside the load balancer are in memory and everything will be missed once the load balancer restarts: all work tasks and result of completed work will be lost. We can store the queues in a different instance

2.	Current code doesn’t handle more than one instance of load balancer, both queues of work tasks and completed should be persisted in a different nodes or should be replicated in load balancer instances

3. In production We would need to keep at least 2 workers ready for handling tasks but this means:

      a.	managing workers will be in load balancer side 

      b.	workers will need to update load balancer when they are going to be terminated 

4.	Monitoring and logs should be in a cloud service or in centralized node: e.g. ec2 instances of workers are terminated and you need to see logs and metrics about what happens there.

5.	Fine tuning of the worker parameters (time for termination, time to launch a new worker...)

6.	Flask installation fails sometimes from the main script in some ec2. It succeeded when we re-run same command in ssh in the same ec2. Strange issue, we search how to make it stable but didn’t succeed: 

     a.	some searches talked about python versions but it’s not our case because it succeeded when running gain

     b.	we think it might be network issue

