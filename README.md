CST8918 - DevOps: Infrastructure as Code  
Prof: Robert McKenney

# LAB-A04 Jenkins on Kubernetes

## Background

### Objective

Set-up Jenkins on your laptop so that you can experiment with creating jobs without using your Azure cloud credits. You will be able to reference this guide later to deploy to Azure Kubernetes Service for a more production lab activities and your final project.

### Use Docker Desktop

Like Lab-A01, you will use your local Docker Desktop as the Kubernetes host. Check to make sure that it is the active context.

```sh
kubectl config current-context
```

If it does not show `docker-desktop` as the output, you need to set it with the `use-context` option.

```sh
kubectl config use-context docker-desktop
```

## Customize the Jenkins container image

Create a customized Dockerfile for the Jenkins Controller Node, that includes some needed plugins.

```sh
FROM jenkins/jenkins:lts-jdk17

# Add plugins for Pipelines with Blue Ocean UI and Kubernetes
RUN jenkins-plugin-cli --plugins blueocean kubernetes

```

Build the container image.

```sh
docker build -t jenkins-controller-kubernetes:1.0 .
```

## Kubernetes configuration

### Create a jenikins namespace

```sh
kubectl create namespace jenkins
```

### Create a deployment file for the Jenkins Controller

Add the code example below to a new file called `jenkins-deployment.yaml`. Make sure that the container image referenced below matches the image name and version tag that you created in the previous step.

Notice the **volumeMounts** section is creating a _persistent_ volume so that configuration meta data is saved in the event that the container fails and needs to be restarted.

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: jenkins
spec:
  replicas: 1
  selector:
    matchLabels:
      app: jenkins
  template:
    metadata:
      labels:
        app: jenkins
    spec:
      containers:
        - name: jenkins
          image: jenkins-controller-kubernetes:1.0
          ports:
            - containerPort: 8080
          volumeMounts:
            - name: jenkins-home
              mountPath: /var/jenkins_home
      volumes:
        - name: jenkins-home
          emptyDir: {}
```

#### Deploy the controller container

```sh
kubectl apply -f jenkins-deployment.yaml -n jenkins
```

Verify that it is running with ...

```sh
kubectl get deployments -n jenkins
```

You should see something like ...

```sh
NAME      READY   UP-TO-DATE   AVAILABLE   AGE
jenkins   1/1     1            1           4m28s
```

### Expose a service to access the Jenkins Controller

The main Jenkins Controller container is running, but it is useless until you create a Kubernetes service to allow ingress from the HTTP port on the host machine (your laptop) to the container instance running in the Kubernetes cluster.

Create a new file called `jenkins-service.yaml`.

```yaml
---
apiVersion: v1
kind: Service
metadata:
  name: jenkins
  namespace: jenkins
spec:
  selector:
    app: jenkins
  ports:
    - port: 80
      targetPort: 8080
  type: LoadBalancer
```

#### Deploy the service

```sh
kubectl create -f jenkins-service.yaml -n jenkins
```

And verify that it worked ...

```sh
kubectl get services -n jenkins

NAME      TYPE           CLUSTER-IP     EXTERNAL-IP   PORT(S)        AGE
jenkins   LoadBalancer   10.109.139.1   localhost     80:31102/TCP   31s
```

The IP address and container port will likely be different than this example, as they are assigned dynamically by your Kubernetes control plane.

### Complete setup

#### Get the admin password

The default user is called `admin` and it's randomly generated password is required for the first login. There are a couple of different ways to find it.

1. It is output in the console log on installation. So, you could use the Docker Desktop GUI to review the container log, or you could use the CLI to display the container log.

First you will need the pod name. It will be formatted like jenkins-<some-random-chrs>

```sh
kubectl get pods -n jenkins
```

Insert that pod name in the _logs_ command to see the console logs for that container.

```sh
kubectl logs <pod_name> -n jenkins
```

The password should be near the end of the logs and look something like ...

```sh
*************************************************************
*************************************************************
*************************************************************

Jenkins initial setup is required. An admin user has been created and a password generated.
Please use the following password to proceed to installation:

31768bf5d2a24ad99e983b8aab780d83

This may also be found at: /var/jenkins_home/secrets/initialAdminPassword

*************************************************************
*************************************************************
*************************************************************
```

2. The simpler option is to show the contents of `/var/jenkins_home/secrets/initialAdminPassword` from the running container.

```sh
kubectl exec -n jenkins -t <pod_name> -- cat /var/jenkins_home/secrets/initialAdminPassword
```

> See [kubectl docs](https://kubernetes.io/docs/reference/generated/kubectl/kubectl-commands#exec) for more info on the _exec_ options.

#### First Login

1. Open the Jenkins Controller in your browser `http://localhost:80`.
2. Unlock the installation with the password obtained in the previous step.
3. Install the default plugins.
4. Create a new user.
5. Confirm the server URL.
6. Start using Jenkins.

#### Some plugins may not have loaded

Navigate to the `Manage Jenkins` tab. If you see a large red notification block showing one or more plugins not loaded correctly:

- choose the plugins menu option
- choose the installed plugins tab (on the left)
- scroll to the bottom and click the button to "restart when jobs are complete"

This will restart Jenkins and should correctly load the Blue Ocean plugin components.

### Configure Jenkins Kubernetes Agents

The main Kubernetes plugin was pre-installed with your custom container image. Now you need to tell Jenkins about your host Kubernetes environment so that it can deploy and manage containers to run your jobs. You will need:

- the URL of the Kubernetes controller and
- the internal cluster URL of the Jenkins pod

```sh
kubectl cluster-info

# outputs similar to this ...

Kubernetes control plane is running at https://kubernetes.docker.internal:6443
CoreDNS is running at https://kubernetes.docker.internal:6443/api/v1/namespaces/kube-system/services/kube-dns:dns/proxy

To further debug and diagnose cluster problems, use 'kubectl cluster-info dump'.
```

Then get the IP address of the Jenkins pod (use the pod_name from earlier) ...

```sh
kubectl describe pod -n jenkins <pod_name>
```

#### Configure Clouds in the Jenkins UI

Go to the `Manage Jenkins > System Configuration > Clouds > New Cloud` menu option.

Name it `local-kubernetes`, check the Kubernetes `type` option below and then click `Create`.

Click the `Kubernetes cloud details` button to reveal the configuration details.

- Copy the _Kubernetes URL_ from the cluster info output e.g.

```sh
https://kubernetes.docker.internal:6443
```

- set the _Kubernetes Namespace_ to `jenkins`

- set the _Jenkins URL_ to the IP address and Port from the describe pod command e.g.

```sh
http://10.1.0.54:8080
```

- And click the `Save` button.

##### Pod Templates

You will now need to create at least one pod template using the `Pod Templates` option from the left-hand menu when looking at the `local-kubernetes` cloud details.

- set the **name** to `jenkins-agent`
- set the **namespace** to `jenkins`
- set the **labels** to `jenkins-agent`
- set the **usage** to `use this node as much as possible`

Leave the rest at their default values and click `Create`

#### Update the default executors

To make sure that Jenkins will use your Kubernetes pods instead of spawning an executor in the main controller pod, change the **usage** option to `Only build jobs with label expressions matching this node`.

Do this on the `Manage Jenkins > Nodes > Built-in Node > Configure` screen.

#### Test it!

Create a test job. It can be anything you like. A simple Freestyle Project that has one build step to echo a message to the console will be enough. e.g. add this as a build step to have it run for 15 seconds -- long enough for you to see the new agent container created and then destroyed.

```sh
#!/bin/bash

for ((i=1; i<=15; i++))
do
  echo $i
  sleep 1
done
```

##### Watch the containers

You can see the new agent created under the **Build Executor Status** in the left-hand menu of the main Jenkins Dashboard.

You can also watch the container activiy using the Kubernetes CLI

```sh
kubectl -n jenkins get pods --watch
```

##### Correcting a permissions error

You may find that the jenkins-agent pod fails to be created and you test job sits in the queue indefinitly. A look through the logs of the main Jenkins controller pod will show a permissions error similar to ...

```sh
io.fabric8.kubernetes.client.KubernetesClientException: Failure executing: POST at: https://kubernetes.docker.internal:6443/api/v1/namespaces/jenkins/pods. Message: pods is forbidden: User "system:serviceaccount:jenkins:default" cannot create resource "pods" in API group "" in the namespace "jenkins". Received status: Status(apiVersion=v1, code=403, details=StatusDetails(causes=[], group=null, kind=pods, name=null, retryAfterSeconds=null, uid=null, additionalProperties={}), kind=Status, message=pods is forbidden: User "system:serviceaccount:jenkins:default" cannot create resource "pods" in API group "" in the namespace "jenkins", metadata=ListMeta(_continue=null, remainingItemCount=null, resourceVersion=null, selfLink=null, additionalProperties={}), reason=Forbidden, status=Failure, additionalProperties={}).
```

You can correct this by running this command to grant the missing permissions.

```sh
kubectl create clusterrolebinding jenkins --clusterrole cluster-admin --serviceaccount=jenkins:default
```

### Production Considerations

This example gets you a Jenkins installation running on your local Kubernetes cluster, which is great for experimentation and learning. When you are ready to setup a production pipeline, you propably want to host it in a public cloud service like AWS, Azure, or GCP. You will need ...

- persistent public IP address and DNS hostname to enable GitHub webhooks.
- robust persistent volume to store Jenkins config and workspace data.
- scalable host nodes to accomodate parallel jobs.

## Demo / Submission

Take a screenshot showing of you Jenkins Dashboard showing at least one job that has run successfully. Make sure that get the whole screen and your username is clearly visible in the upper right corner.

Submit on Brightspace.
