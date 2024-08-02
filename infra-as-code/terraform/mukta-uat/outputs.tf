output "aws_db_instance_id" {
  value = "${aws_db_instance.db.id}"
}

output "cluster_endpoint" {
  description = "Endpoint for EKS control plane."
  value       = "${aws_eks_cluster.eks.endpoint}"
}