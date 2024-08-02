terraform {
  backend "s3" {
    bucket = "mukta-uat-terraform-state"
    key = "terraform"
    region = "ap-south-1"
  }
}

data "aws_caller_identity" "current" {}

data "tls_certificate" "thumb" {
  url = "${var.cluster_oidc_url}"
}

data "aws_ssm_parameter" "eks_ami" {
  name = "/aws/service/eks/optimized-ami/${var.kubernetes_version}/amazon-linux-2/recommended/image_id"
}

provider "kubernetes" {
  load_config_file = true
  config_path      = "/Users/shivam/.kube/mukta-uat"
  version          = "~> 1.11"
}

resource "aws_db_instance" "db" {
  allocated_storage                     = "10"
  availability_zone                     = "ap-south-1b"
  backup_retention_period               = "7"
  backup_target                         = "region"
  backup_window                         = "20:18-20:48"
  ca_cert_identifier                    = "rds-ca-2019"
  copy_tags_to_snapshot                 = "true"
  customer_owned_ip_enabled             = "false"
  db_name                               = "${var.db_name}"
  db_subnet_group_name                  = "db-subnet-group-mukta-uat"
  dedicated_log_volume                  = "false"
  deletion_protection                   = "false"
  engine                                = "postgres"
  engine_lifecycle_support              = "open-source-rds-extended-support"
  engine_version                        = "${var.db_version}"
  iam_database_authentication_enabled   = "false"
  identifier                            = "${var.cluster_name}-db"
  instance_class                        = "db.t3.medium"
  iops                                  = "0"
  license_model                         = "postgresql-license"
  maintenance_window                    = "wed:12:36-wed:13:06"
  max_allocated_storage                 = "0"
  monitoring_interval                   = "0"
  multi_az                              = "false"
  network_type                          = "IPV4"
  option_group_name                     = "default:postgres-12"
  parameter_group_name                  = "default.postgres12"
  performance_insights_enabled          = "false"
  performance_insights_retention_period = "0"
  port                                  = "5432"
  publicly_accessible                   = "false"
  storage_encrypted                     = "false"
  storage_throughput                    = "0"
  storage_type                          = "gp2"
  skip_final_snapshot                   = "true"
  apply_immediately                     = "true"
  allow_major_version_upgrade           = "true"
  auto_minor_version_upgrade            = "false"

  tags = {
    KubernetesCluster = "${var.cluster_name}"
    Name              = "${var.cluster_name}-db"
    environment       = "${var.cluster_name}"
  }

  tags_all = {
    KubernetesCluster = "${var.cluster_name}"
    Name              = "${var.cluster_name}-db"
    environment       = "${var.cluster_name}"
  }

  username               = "${var.db_username}"
  vpc_security_group_ids = ["sg-0cd6088bc786c7e57"]
}


resource "aws_eks_cluster" "eks" {
  access_config {
    authentication_mode                         = "CONFIG_MAP"
    bootstrap_cluster_creator_admin_permissions = "true"
  }

  bootstrap_self_managed_addons = "false"

  kubernetes_network_config {
    ip_family         = "ipv4"
    service_ipv4_cidr = "10.100.0.0/16"
  }

  name     = "${var.cluster_name}"
  role_arn = "arn:aws:iam::880678429748:role/mukta-uat2023042006164051890000000b"

  tags = {
    KubernetesCluster                 = "${var.cluster_name}"
    "kubernetes.io/cluster/mukta-uat" = "owned"
  }

  tags_all = {
    KubernetesCluster                 = "${var.cluster_name}"
    "kubernetes.io/cluster/mukta-uat" = "owned"
  }

  version = "${var.kubernetes_version}"

  vpc_config {
    endpoint_private_access = "false"
    endpoint_public_access  = "true"
    public_access_cidrs     = ["0.0.0.0/0"]
    security_group_ids      = ["sg-0ff6dc48f50dcca02"]
    subnet_ids              = ["subnet-071be1437a83e45f6", "subnet-081f414b49b1cbf99", "subnet-0a5a6062fc679e8ac", "subnet-0ff6ce7f80e4edd07"]
  }
}

resource "aws_autoscaling_group" "asg" {
  availability_zones        = ["ap-south-1b"]
  capacity_rebalance        = "false"
  default_cooldown          = "300"
  default_instance_warmup   = "0"
  desired_capacity          = "${var.number_of_worker_nodes}"
  force_delete              = "false"
  health_check_grace_period = "300"
  health_check_type         = "EC2"
  launch_configuration      = "mukta-uat-spot2023042006250934230000001d"
  max_instance_lifetime     = "0"
  max_size                  = "${var.number_of_worker_nodes}"
  metrics_granularity       = "1Minute"
  min_size                  = "${var.number_of_worker_nodes}"
  name_prefix               = "${var.cluster_name}-spot"
  protect_from_scale_in     = "false"
  service_linked_role_arn   = "arn:aws:iam::880678429748:role/aws-service-role/autoscaling.amazonaws.com/AWSServiceRoleForAutoScaling"
  suspended_processes       = ["AZRebalance"]

  tag {
    key                 = "KubernetesCluster"
    propagate_at_launch = "true"
    value               = "${var.cluster_name}"
  }

  tag {
    key                 = "Name"
    propagate_at_launch = "true"
    value               = "${var.cluster_name}-spot-eks_asg"
  }

  tag {
    key                 = "k8s.io/cluster/${var.cluster_name}"
    propagate_at_launch = "true"
    value               = "owned"
  }

  tag {
    key                 = "kubernetes.io/cluster/${var.cluster_name}"
    propagate_at_launch = "true"
    value               = "owned"
  }

  wait_for_capacity_timeout = "10m"
}

resource "aws_iam_role" "eks_iam" {
  name = "${var.cluster_name}-eks"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Sid = "EKSWorkerAssumeRole"
        Effect = "Allow",
        Principal = {
          Federated = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:oidc-provider/${replace(var.cluster_oidc_url, "https://", "")}"
        },
        Action = "sts:AssumeRoleWithWebIdentity",
        Condition = {
          StringEquals = {
            "${replace(var.cluster_oidc_url, "https://", "")}:sub" = "system:serviceaccount:kube-system:ebs-csi-controller-sa"
          }
        }
      }
    ]
  })
}

resource "aws_iam_policy" "custom_ebs_policy" {
  name        = "${var.cluster_name}-ebs"
  description = "Custom policy for EBS volume management"
  policy      = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "Statement1"
        Effect = "Allow"
        Action = [
          "ec2:CreateVolume",
          "ec2:AttachVolume",
          "ec2:CreateTags"
        ]
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "cluster_AmazonEBSCSIDriverPolicy" {
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy"
  role       = "${aws_iam_role.eks_iam.name}"
}

resource "aws_iam_role_policy_attachment" "cluster_AmazonEC2FullAccess" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2FullAccess"
  role       = "${aws_iam_role.eks_iam.name}"
}

resource "aws_iam_role_policy_attachment" "cluster_custom_ebs" {
  policy_arn = aws_iam_policy.custom_ebs_policy.arn
  role       = "${aws_iam_role.eks_iam.name}"
}

resource "aws_iam_openid_connect_provider" "eks_oidc_provider" {
  client_id_list = ["sts.amazonaws.com"]
  thumbprint_list = ["${data.tls_certificate.thumb.certificates.0.sha1_fingerprint}"] # This should be empty or provide certificate thumbprints if needed
  url            = "${var.cluster_oidc_url}" # Replace with the OIDC URL from your EKS cluster details
}

resource "aws_eks_addon" "kube_proxy" {
  cluster_name      = "${aws_eks_cluster.eks.name}"
  addon_name        = "kube-proxy"
  resolve_conflicts = "OVERWRITE"
}
resource "aws_eks_addon" "core_dns" {
  cluster_name      = "${aws_eks_cluster.eks.name}"
  addon_name        = "coredns"
  resolve_conflicts = "OVERWRITE"
}
resource "aws_eks_addon" "aws_ebs_csi_driver" {
  cluster_name      = "${aws_eks_cluster.eks.name}"
  addon_name        = "aws-ebs-csi-driver"
  resolve_conflicts = "OVERWRITE"
}