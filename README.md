# aws-auth-validator-webhook
Validation webhook to validate aws-auth configMap in the kube-system namespace
### Steps to setup:
1. Label the namespace:
   ~~~bash
   kubectl label ns kube-system name=kube-system
   ~~~

2. Create Docker image from the Dockerfile

    ~~~bash
    aws ecr-public create-repository \
     --repository-name webhook \
     --region <region>
    ~~~

    ~~~bash
    aws ecr-public get-login-password --region <region> | docker login --username AWS --password-stdin public.ecr.aws/xxxxxxx
    docker build --network=host -t webhook .
    docker tag webhook:latest public.ecr.aws/xxxxxxx/webhook:latest
    docker push public.ecr.aws/xxxxxxx/webhook:latest
    ~~~

3. Generate certificates using the bash script
     ~~~bash
     bash generatecerts.sh --service aws-auth-validator-svc --secret aws-auth-validator-certs --namespace kube-system
     ~~~

4. Enable OIDC provider, create IAM Policy and create IAM service account:
     ~~~bash
     bash setup_irsa.sh <region> <cluster_name> <namespace>
     ~~~

     ~~~bash
     eg: bash setup_irsa.sh us-east-1 training kube-system
     ~~~

5. **PRODUCTION** - Apply the label to the aws-auth to make sure that it's detected by the webhook
     ~~~bash
     kubectl -n kube-system label cm aws-auth name=aws-auth
     ~~~

6. Generate the manifest.yaml and apply.
     ~~~bash
     bash manifest_generate.sh --iamge public.ecr.aws/xxxxxxx/webhook:latest  \
          --cluster <cluster_name> \
          --region <region> \
          --arn arn:aws:iam::XXXXXXXXXXXX:user/user
     ~~~

     ~~~bash
     kubectl apply -f manifest.yaml
     ~~~

### Troubleshooting:
     kubectl get pods -n kube-system -l app=aws-auth-validator
     kubectl describe deploy -n kube-system aws-auth-validator
     kubectl logs -n kube-system -l app=aws-auth-validator -f
     kubectl edit -n kube-system cm aws-auth
