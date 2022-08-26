## Source
# 1. https://aws.amazon.com/blogs/opensource/introducing-fine-grained-iam-roles-service-accounts/

# Required Variables
region=$1
clusterName=$2
namespace=$3

[[ -z "$region" || -z "$clusterName" || -z "$namespace" ]] && echo "Assign region, clusterName and namespace variables to something :/  Eg: steps.sh us-east-1 demo-cluster" && exit 0

# Optional - Change me to use non-defaul values
serviceAccountName="aws-auth-validator"

# Check if eksctl, awsCli and kubectl exist
[[ ! `eksctl --help` ]] && echo "eksctl does not exist. Please install it first" && exit 1
[[ ! `kubectl --help` ]] && echo "kubectl does not exist. Please install it first" && exit 1
[[ ! `aws help` ]] && echo "awscli does not exist. Please install it first" && exit 1
[[ ! `jq --help` ]] && echo "jq does not exist. Please install it first" && exit 1

# Check Kubernetes Version
requiredK8sVersion="115"
K8sVersion=$(eksctl get cluster --name $clusterName | cut -f 2 | tr -d "\n" | tr -d ".")
[[ $K8sVersion -lt $requiredK8sVersion ]] && echo "Need Kubernetes Version 1.15 or greater..Exiting" && exit 1

# Check Eksctl Version
#requiredEksctlVersion="050"
#EksctlVersion=$(eksctl version | awk -F ':"' '{print $4}' | sed 's/[^a-zA-Z0-9]//g')
#[[ $EksctlVersion -lt $requiredEksctlVersion ]] && echo "Need eksctl Version greater than 0.5.0 ..Exiting" && exit 1

# Associate OIDC
eksctl utils associate-iam-oidc-provider --cluster $clusterName --approve

policyARN=$(aws iam list-policies | jq '.Policies[] | select(.PolicyName=="aws-auth-validator") | .Arn')
if [ -z $policyARN ]; then
	aws iam create-policy --region ${region} --policy-name aws-auth-validator --policy-document file://policy.json
fi
sleep 2
echo "IAM Policy Created: ${policyARN}"

# Create Service account
eksctl delete iamserviceaccount --name $serviceAccountName --namespace ${namespace} --cluster $clusterName
sleep 2
for x in $(seq 10); do
    eksctl create iamserviceaccount --name $serviceAccountName --namespace ${namespace} --cluster $clusterName --attach-policy-arn $policyARN --approve
    getiamserviceaccount=$(eksctl get iamserviceaccount --name $serviceAccountName --namespace ${namespace} --cluster $clusterName -o json |jq '.[] | .status.roleARN')
    if [[ ${getiamserviceaccount} != '' ]]; then
        break
    fi
    sleep 1
done

RoleARN=$(kubectl -n ${namespace} get sa $serviceAccountName -o jsonpath='{.metadata.annotations.eks\.amazonaws\.com/role\-arn}')

echo "Service accouint created and the IAM Role ARN is: ${RoleARN}"
