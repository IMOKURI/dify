output "load_balancer_ip" {
  description = "Load Balancer IP address"
  value       = google_compute_global_address.dify_lb_ip.address
}

output "vm_instance_name" {
  description = "VM instance name"
  value       = google_compute_instance.dify_vm.name
}

output "vm_instance_ip" {
  description = "VM instance external IP"
  value       = google_compute_instance.dify_vm.network_interface[0].access_config[0].nat_ip
}

output "vm_zone" {
  description = "VM instance zone"
  value       = google_compute_instance.dify_vm.zone
}

output "ssh_command" {
  description = "SSH command to connect to the instance"
  value       = "gcloud compute ssh ${google_compute_instance.dify_vm.name} --zone ${var.zone} --project ${var.project_id}"
}

output "https_url" {
  description = "HTTPS URL to access the application"
  value       = var.domain_name != "" ? "https://${var.domain_name}" : "https://${google_compute_global_address.dify_lb_ip.address}"
}
