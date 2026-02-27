#!/bin/sh

pushd ..

# Configure WAF 1.
printf "\nConfigure WAF 1 ...\n"
kubectl apply -f policies/waf-rules-configmap-1.yaml

popd