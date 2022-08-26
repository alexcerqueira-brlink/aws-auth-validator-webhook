#!/bin/bash

set -e

PROG_IMAGE=$1
PROG_CLUSTER_NAME=$2
PROG_CLUSTER_REGION=$3
PROG_CABUNDLE="$(bash ./generatecerts.sh --service aws-auth-validator-svc --secret aws-auth-validator-certs --namespace kube-system)"

[ -z $PROG_IMAGE ] && echo "Enter with the Image" && exit 0
[ -z $PROG_CLUSTER_NAME ] && echo "Enter with the Cluster Name" && exit 0
[ -z $PROG_CLUSTER_REGION ] && echo "Enter with the Cluster Region" && exit 0
[ -z $PROG_CABUNDLE ] && exit 0

#export PROG_IMAGE="public.ecr.aws/t4h9q3m4/webhook:latest"
#export PROG_CLUSTER_NAME="k8s-brlink-dev"
#export PROG_CLUSTER_REGION="us-east-1"

cat << EOF > ./manifest.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: aws-auth-validator
  namespace: kube-system
  labels:
    app: aws-auth-validator
spec:
  replicas: 1
  selector:
    matchLabels:
      app: aws-auth-validator
  template:
    metadata:
      labels:
        app: aws-auth-validator
    spec:
      # SA corresponds to the SA created by the IRSA setup script.
      serviceAccountName: aws-auth-validator
      containers:
        - name: aws-auth-validator
          image: $PROG_IMAGE
          env:

            # Mandatory values. Change these
            - name: CLUSTER_NAME
              value: $PROG_CLUSTER_NAME
            - name: CLUSTER_REGION
              value: $PROG_CLUSTER_REGION

            # Optional parameter. Defaults to None
            # Specify any additional Roles/IAM-users that needs to be present in the aws-auth. This will prevent those roles/users getting locked out intentionally or otherwise.
            # Accept comma-saperated values without spaces. Eg - value: "arn:aws:iam::111122223333:role/AmazonEKSFargatePodExecutionRole,arn:aws:iam::111122223333:user/ops-user"
#           - name: ADDITIONAL_ROLES
#             value: "arn:aws:iam::XXXXXXXXXXXX:user/test"

            # Optional parameter. Defaults to None
            # IAM Roles defined via REJECT_ROLES environment variable in the Deployment will not be allowed in the aws-auth. This is particularly useful where a specific user/Role should be denied access and also helps in cases where cluster creator should not be defined in aws-auth as best practice. REJECT_ROLES env variable accepts comma-separated values
            #            - name: REJECT_ROLES
            #              value: ""

            # If TESTING is set to True, webhook will intercept configMaps with any name as long as it has label name=aws-auth and perform validation. This is useful if testing within kube-system namespace but you don't want to test on actual aws-auth configMap  

            # If TESTING is set to False, webhook will intercept configMaps with name aws-auth as long as it has label name=aws-auth and perform validation. Other configMaps that have a different name but have label name=aws-aut will be allowed to pass through without performing any validation

            # Possible values: "True or False"
            # Default value: True
            - name: TESTING
              value: "True"
          imagePullPolicy: Always
          volumeMounts:
            - name: aws-auth-validator-certs
              mountPath: /etc/webhook/certs
              readOnly: true
      volumes:
        - name: aws-auth-validator-certs
          secret:
            secretName: aws-auth-validator-certs
---
apiVersion: v1
kind: Service
metadata:
  name: aws-auth-validator-svc
  namespace: kube-system
  labels:
    app: aws-auth-validator
spec:
  ports:
  - port: 443
    targetPort: 443
  selector:
    app: aws-auth-validator           
---
apiVersion: admissionregistration.k8s.io/v1
kind: ValidatingWebhookConfiguration
metadata:
  name: aws-auth-validator
webhooks:
- admissionReviewVersions:
  - v1beta1
  clientConfig:
    caBundle: $PROG_CABUNDLE
    service:
      name: aws-auth-validator-svc
      namespace: kube-system
      path: /validate/configmaps
      port: 443
  failurePolicy: Fail
  matchPolicy: Exact
  # change me. However, will work with the default value
  name: validatingwebhook.test.com
  namespaceSelector:
    matchExpressions:
    - key: name
      operator: In
      values:
      - kube-system
  objectSelector:
    matchLabels:
      name: aws-auth
  rules:
  - apiVersions:
    - '*'
    apiGroups: ["*"]
    operations:
    - CREATE
    - UPDATE
    - DELETE
    resources: ["configmaps"]
    scope: Namespaced
  sideEffects: None
  timeoutSeconds: 30
EOF