# Gloo Gateway Reproducer Template

## Installation

Add Gloo Gateway Helm repo:
```
helm repo add glooe https://storage.googleapis.com/gloo-ee-helm
```

Export your Gloo Gateway License Key to an environment variable:
```
export GLOO_GATEWAY_LICENSE_KEY={your license key}
```

Install Gloo Gateway:
```
cd install
./install-gloo-gateway-with-helm.sh
```

> NOTE
> The Gloo Gateway version that will be installed is set in a variable at the top of the `install/install-gloo-gateway-with-helm.sh` installation script.

## Setup the environment

Run the `install/setup.sh` script to setup the environment:

- Create the required namespaces
- Deploy the Gateways (Gloo Egde API and K8S Gateway API)
- Deploy the HTTPBin application
- Deploy the Reference Grants
- Deploy the VirtualService (Gloo Edge API)
- Deploy the HTTPRoute (K8S Gateway API)

```
./setup.sh
```

## Access the HTTPBin application

__Gloo Edg API:__

```
./curl-request-ge-api.sh
```

or

```
curl -v http://api.example.com:81/get
```

__K8S Gateway API:__

```
./curl-request-g8s-gw-api.sh
```

or

```
curl -v http://api.example.com:81/get
```