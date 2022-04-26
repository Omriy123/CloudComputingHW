#!/bin/sh

git clone git@github.com:Omriy123/CloudComputingHW.git

aws cloudformation create-stack --stack-name hw1stack --template-body file://CloudComputingHW/CloudComputinHW1.yaml --capabilities CAPABILITY_NAMED_IAM

