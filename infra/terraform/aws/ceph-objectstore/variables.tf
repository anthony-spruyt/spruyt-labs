# variable "project" {
#   type        = string
#   description = "Project tag and name prefix"
#   default     = "spruyt-labs"
# }
#
# variable "environment" {
#   type        = string
#   description = "Environment tag and name suffix"
#   default     = "prod"
# }
#
variable "aws_region" {
  type        = string
  description = "AWS region for resources"
  default     = "ap-southeast-4" # ap-southeast-2 = Sydney ; ap-southeast-4 = Melbourne
}
