# Create EKS Cluster via AWS Console

## Step-by-Step Instructions for AWS Console

### Step 1: Go to EKS Console

1. Open https://console.aws.amazon.com/eks/
2. Make sure you're in **us-east-1** region (top right corner)
3. Click **"Add cluster"** → **"Create"**

### Step 2: Configure Cluster

**Cluster Configuration:**
- **Name:** `cfk-demo`
- **Kubernetes version:** `1.31`
- **Cluster service role:** 
  - If you don't have one, click **"Create role"** → Follow the wizard → Come back
  - Select the role you created

**Networking:**
- **VPC:** Create new or select existing
- **Subnets:** Select at least 2 public subnets in different AZs
- **Security groups:** Use default
- **Cluster endpoint access:** Public

**Logging:** Leave disabled for demo

Click **"Next"** → **"Next"** → **"Create"**

**Wait 10-15 minutes** for cluster creation.

---

### Step 3: Add Node Group

Once the cluster shows **"Active"**:

1. Click on your cluster name `cfk-demo`
2. Go to **"Compute"** tab
3. Click **"Add node group"**

**Node Group Configuration:**
- **Name:** `cfk-nodes`
- **Node IAM role:** 
  - If you don't have one, create with these policies:
    - AmazonEKSWorkerNodePolicy
    - AmazonEKS_CNI_Policy
    - AmazonEC2ContainerRegistryReadOnly
  - Select the role

**Node Group Compute Configuration:**
- **AMI type:** Amazon Linux 2023
- **Capacity type:** On-Demand
- **Instance types:** m5.xlarge
- **Disk size:** 100 GB

**Node Group Scaling Configuration:**
- **Desired size:** 3
- **Minimum size:** 3
- **Maximum size:** 6

**Node Group Network Configuration:**
- **Subnets:** Select the same subnets as cluster (public ones)

Click **"Next"** → **"Next"** → **"Create"**

**Wait 5-10 minutes** for nodes to be ready.

---

### Step 4: Configure kubectl Access

Once cluster and nodes are **"Active"**:

```bash
# Update kubeconfig to access the cluster
aws eks update-kubeconfig --region us-east-1 --name cfk-demo

# Verify access
kubectl get nodes
# Should show 3 nodes in Ready state
```

---

## Alternative: Use CloudFormation Template

If the console doesn't work, try this CloudFormation approach:

### Create CloudFormation Stack

1. Go to https://console.aws.amazon.com/cloudformation/
2. Click **"Create stack"** → **"With new resources"**
3. Choose **"Upload a template file"**
4. Upload the template file below
5. Click **"Next"**

**Stack Details:**
- **Stack name:** `cfk-demo-cluster`
- **ClusterName:** `cfk-demo`
- **KubernetesVersion:** `1.31`

Click **"Next"** → **"Next"** → Check **"I acknowledge..."** → **"Submit"**

---

## CloudFormation Template

Save this as `eks-cluster-cfn.yaml`:

```yaml
AWSTemplateFormatVersion: '2010-09-09'
Description: 'EKS Cluster for Confluent Platform Demo'

Parameters:
  ClusterName:
    Type: String
    Default: cfk-demo
    Description: Name of the EKS cluster
  
  KubernetesVersion:
    Type: String
    Default: '1.31'
    Description: Kubernetes version
    AllowedValues:
      - '1.29'
      - '1.30'
      - '1.31'
      - '1.32'
      - '1.33'

Resources:
  # VPC
  VPC:
    Type: AWS::EC2::VPC
    Properties:
      CidrBlock: 192.168.0.0/16
      EnableDnsHostnames: true
      EnableDnsSupport: true
      Tags:
        - Key: Name
          Value: !Sub '${ClusterName}-vpc'

  # Internet Gateway
  InternetGateway:
    Type: AWS::EC2::InternetGateway
    Properties:
      Tags:
        - Key: Name
          Value: !Sub '${ClusterName}-igw'

  VPCGatewayAttachment:
    Type: AWS::EC2::VPCGatewayAttachment
    Properties:
      VpcId: !Ref VPC
      InternetGatewayId: !Ref InternetGateway

  # Public Subnets
  PublicSubnet1:
    Type: AWS::EC2::Subnet
    Properties:
      VpcId: !Ref VPC
      CidrBlock: 192.168.0.0/19
      AvailabilityZone: !Select [0, !GetAZs '']
      MapPublicIpOnLaunch: true
      Tags:
        - Key: Name
          Value: !Sub '${ClusterName}-public-subnet-1'
        - Key: kubernetes.io/role/elb
          Value: '1'

  PublicSubnet2:
    Type: AWS::EC2::Subnet
    Properties:
      VpcId: !Ref VPC
      CidrBlock: 192.168.32.0/19
      AvailabilityZone: !Select [1, !GetAZs '']
      MapPublicIpOnLaunch: true
      Tags:
        - Key: Name
          Value: !Sub '${ClusterName}-public-subnet-2'
        - Key: kubernetes.io/role/elb
          Value: '1'

  # Route Table
  PublicRouteTable:
    Type: AWS::EC2::RouteTable
    Properties:
      VpcId: !Ref VPC
      Tags:
        - Key: Name
          Value: !Sub '${ClusterName}-public-rt'

  PublicRoute:
    Type: AWS::EC2::Route
    DependsOn: VPCGatewayAttachment
    Properties:
      RouteTableId: !Ref PublicRouteTable
      DestinationCidrBlock: 0.0.0.0/0
      GatewayId: !Ref InternetGateway

  PublicSubnet1RouteTableAssociation:
    Type: AWS::EC2::SubnetRouteTableAssociation
    Properties:
      SubnetId: !Ref PublicSubnet1
      RouteTableId: !Ref PublicRouteTable

  PublicSubnet2RouteTableAssociation:
    Type: AWS::EC2::SubnetRouteTableAssociation
    Properties:
      SubnetId: !Ref PublicSubnet2
      RouteTableId: !Ref PublicRouteTable

  # EKS Cluster Security Group
  ClusterSecurityGroup:
    Type: AWS::EC2::SecurityGroup
    Properties:
      GroupDescription: Security group for EKS cluster
      VpcId: !Ref VPC
      Tags:
        - Key: Name
          Value: !Sub '${ClusterName}-cluster-sg'

  # EKS Cluster IAM Role
  EKSClusterRole:
    Type: AWS::IAM::Role
    Properties:
      AssumeRolePolicyDocument:
        Version: '2012-10-17'
        Statement:
          - Effect: Allow
            Principal:
              Service: eks.amazonaws.com
            Action: sts:AssumeRole
      ManagedPolicyArns:
        - arn:aws:iam::aws:policy/AmazonEKSClusterPolicy
      Tags:
        - Key: Name
          Value: !Sub '${ClusterName}-cluster-role'

  # EKS Cluster
  EKSCluster:
    Type: AWS::EKS::Cluster
    Properties:
      Name: !Ref ClusterName
      Version: !Ref KubernetesVersion
      RoleArn: !GetAtt EKSClusterRole.Arn
      ResourcesVpcConfig:
        SecurityGroupIds:
          - !Ref ClusterSecurityGroup
        SubnetIds:
          - !Ref PublicSubnet1
          - !Ref PublicSubnet2
        EndpointPublicAccess: true
        EndpointPrivateAccess: false

  # Node IAM Role
  NodeInstanceRole:
    Type: AWS::IAM::Role
    Properties:
      AssumeRolePolicyDocument:
        Version: '2012-10-17'
        Statement:
          - Effect: Allow
            Principal:
              Service: ec2.amazonaws.com
            Action: sts:AssumeRole
      ManagedPolicyArns:
        - arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy
        - arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy
        - arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly
      Tags:
        - Key: Name
          Value: !Sub '${ClusterName}-node-role'

  # EKS Node Group
  NodeGroup:
    Type: AWS::EKS::Nodegroup
    DependsOn: EKSCluster
    Properties:
      ClusterName: !Ref ClusterName
      NodegroupName: cfk-nodes
      NodeRole: !GetAtt NodeInstanceRole.Arn
      Subnets:
        - !Ref PublicSubnet1
        - !Ref PublicSubnet2
      ScalingConfig:
        DesiredSize: 3
        MinSize: 3
        MaxSize: 6
      InstanceTypes:
        - m5.xlarge
      DiskSize: 100
      AmiType: AL2023_x86_64_STANDARD
      Tags:
        Environment: demo
        role: confluent

Outputs:
  ClusterName:
    Description: EKS Cluster Name
    Value: !Ref EKSCluster
  
  ClusterEndpoint:
    Description: EKS Cluster Endpoint
    Value: !GetAtt EKSCluster.Endpoint
  
  ClusterArn:
    Description: EKS Cluster ARN
    Value: !GetAtt EKSCluster.Arn

  KubeconfigCommand:
    Description: Command to configure kubectl
    Value: !Sub 'aws eks update-kubeconfig --region ${AWS::Region} --name ${ClusterName}'
```

---

## Troubleshooting

### If You Still Get SCP Errors

The SCP policy is blocking at the organization level. You'll need to:

1. **Contact your AWS Organization admin** with this info:
   - Account ID: `492737776546`
   - User: `cstevenson-rhel9-rsyslog`
   - Required actions: `eks:CreateCluster`, `ec2:CreateVPC`, `ec2:CreateSubnet`
   - SCP blocking: `p-bczrhmm4` in organization `368821881613`

2. **Request:**
   - Temporary exemption for your account, OR
   - Have them create the cluster for you using the CloudFormation template above

### If CloudFormation Works But eksctl Doesn't

That's fine! The CloudFormation approach creates the same cluster. Once the stack shows **"CREATE_COMPLETE"**:

```bash
aws eks update-kubeconfig --region us-east-1 --name cfk-demo
kubectl get nodes
```

Then continue with the AWS deployment guide from **Step 2** (EBS CSI Driver).

---

## Summary

**Easiest Path:**
1. Use CloudFormation template above via AWS Console
2. Wait for CREATE_COMPLETE (~20 minutes)
3. Configure kubectl access
4. Continue with deployment guide Step 2

**If that fails:**
Contact AWS admin for SCP exemption or cluster creation assistance.
