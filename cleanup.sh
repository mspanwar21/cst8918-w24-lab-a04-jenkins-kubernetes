#!/bin/sh
kubectl delete deployment jenkins -n jenkins
kubectl delete service jenkins -n jenkins
kubectl delete namespace jenkins