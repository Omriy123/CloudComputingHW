# CloudComputingHW
## H.W. 1
### Our solution
Our template will create a aws stack that includes:
1. DynamoDb table to store the parking lot entries
2. An api gateway for entry and exit to the parking lot
3. A lambda function that for handling entry and exit calls, the lambda will insert to the dynamodb table and retrieve data when needed
4. All other needed configurations for lambda and api gateway (Integration,Permissions,Routes,IAM Role)

### Using  aws CLI to create the stack
1. Install aws CLI https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html
2. Configure aws https://docs.aws.amazon.com/cli/latest/userguide/getting-started-quickstart.html
3. Download the .yaml file
4. run the following line in the CLI:

    `aws cloudformation create-stack --stack-name STACKNAME --template-body file://FILEPATH/CloudComputingHW1.yaml --capabilities CAPABILITY_NAMED_IAM`

Alternatively, if you are using linux you can run the createStack.sh script to clone the .yaml and create the stack
