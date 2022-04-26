# CloudComputingHW
## H.W. 1
Install aws CLI https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html
Configure aws https://docs.aws.amazon.com/cli/latest/userguide/getting-started-quickstart.html
Download the .yaml file
run the following line in the cli:
  aws cloudformation create-stack --stack-name STACKNAME --template-body file://FILEPATH/CloudComputingHW1.yaml --capabilities CAPABILITY_NAMED_IAM
