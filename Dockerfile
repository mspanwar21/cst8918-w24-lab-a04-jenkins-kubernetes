FROM jenkins/jenkins:lts-jdk17

# Add plugins for Pipelines with Blue Ocean UI and Kubernetes
RUN jenkins-plugin-cli --plugins blueocean kubernetes
