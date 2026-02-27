#!/bin/sh

pushd ..

# Configure WAF 1.
printf "\nDelete WAF config-maps ...\n"
kubectl delete -f policies/waf-rules-configmap-1.yaml
kubectl delete -f policies/waf-rules-configmap-2.yaml

# Delete VirtualHostOption
kubectl delete -f policies/waf-virtualhostoption.yaml

popd