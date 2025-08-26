variable "project" {
  type        = string
  description = "Project tag and name prefix"
  default     = "spruyt-labs"
}

variable "environment" {
  type        = string
  description = "Environment tag and name suffix"
  default     = "prod"
}
