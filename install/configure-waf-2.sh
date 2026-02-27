#!/bin/sh

pushd ..

# Configure WAF 2.
printf "\nConfigure WAF 2 ...\n"
kubectl apply -f policies/waf-rules-configmap-2.yaml

popd