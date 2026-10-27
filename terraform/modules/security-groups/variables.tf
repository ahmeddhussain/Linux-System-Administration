variable "name_prefix" {
  description = "Prefix for resource names"
  type        = string
}

variable "vpc_id" {
  description = "ID of the VPC the security groups belong to"
  type        = string
}

variable "roles" {
  description = "Host roles; one security group is created per role"
  type        = set(string)
}

variable "flows" {
  description = "Allowed connections between roles. Anything not listed is denied."
  type = map(object({
    from        = string
    to          = string
    protocol    = string
    port        = number
    description = string
  }))

  validation {
    condition = alltrue([
      for f in values(var.flows) : contains(var.roles, f.from) && contains(var.roles, f.to)
    ])
    error_message = "Every flow must use roles that are listed in var.roles."
  }
}

variable "cidr_ingress" {
  description = "Allowed inbound connections from IP ranges"
  type = map(object({
    role        = string
    cidr        = string
    protocol    = string
    port        = number
    description = string
  }))

  validation {
    condition     = alltrue([for r in values(var.cidr_ingress) : contains(var.roles, r.role)])
    error_message = "Every cidr_ingress entry must use a role that is listed in var.roles."
  }
}

variable "cidr_egress" {
  description = "Allowed outbound connections to IP ranges"
  type = map(object({
    role        = string
    cidr        = string
    protocol    = string
    port        = number
    description = string
  }))

  validation {
    condition     = alltrue([for r in values(var.cidr_egress) : contains(var.roles, r.role)])
    error_message = "Every cidr_egress entry must use a role that is listed in var.roles."
  }
}