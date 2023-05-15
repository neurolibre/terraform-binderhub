variable "ip" {
  description = "ip address of the master"
}

variable "domain" {
  description = "Domain name"
}

variable "TLS_name" {
  description = "TLS certificate name, same as domain but with dashes instead of points"
}

variable "TLS_email" {
  description = "Email address used to register TLS certificate"
}

variable "mem_alloc_gb" {
  description = "RAM allocation per user"
}

variable "cpu_alloc" {
  description = "CPU allocation per user (floating point values are supported)"
}

variable "admin_user" {
  description = "User with root access"
}

variable "binder_version" {
  description = "binderhub helm chart version - https://jupyterhub.github.io/helm-chart/#development-releases-binderhub"
}

variable "docker_registry" {
  description = "Docker registry url"
  default     = "docker.io"
}

variable "docker_id" {
  description = "Docker hub username"
}

variable "docker_password" {
  description = "Docker hub password"
}

