variable "name" {
  type        = string
  description = "The name of the pipeline"
}

variable "artifact_bucket_name" {
  type        = string
  description = "The S3 Bucket name of artifacts."
}

variable "s3_source_object_key" {
  type        = string
  description = "程式碼來源物件位置"
}


variable "cluster_name" {
  type        = string
  description = "The name of the ECS Cluster."
}

variable "service_name" {
  type        = string
  description = "The name of the ECS Service."
}

variable "encryption_key_id" {
  default     = ""
  type        = string
  description = "The KMS key ARN or ID."
}


variable "file_name" {
  default     = "imagedefinitions.json"
  type        = string
  description = "The file name of the image definitions."
}

variable "secret_token" {
  default     = ""
  type        = string
  description = "The secret token for the GitHub webhook."
}

variable "filter_json_path" {
  default     = "$.ref"
  type        = string
  description = "The JSON path to filter on."
}

variable "filter_match_equals" {
  default     = "refs/heads/{Branch}"
  type        = string
  description = "The value to match on (e.g. refs/heads/{Branch})."
}

variable "webhook_events" {
  default     = ["push"]
  type        = list(string)
  description = "A list of events which should trigger the webhook."
}

variable "iam_path" {
  default     = "/"
  type        = string
  description = "Path in which to create the IAM Role and the IAM Policy."
}

variable "description" {
  default     = "Managed by Terraform"
  type        = string
  description = "The description of the all resources."
}

variable "tags" {
  default     = {}
  type        = map(string)
  description = "A mapping of tags to assign to all resources."
}

variable "alb_listen_arns" {
  type        = list(string)
  description = "AWS alb listen ARN"
}

variable "alb_listen_testing_arns" {
  type        = list(string)
  description = "AWS alb listen testing ARN"
}

variable "alb_target_group_blue_name" {
  type        = string
  description = "AWS ALB Target Group Name"
}

variable "alb_target_group_green_name" {
  type        = string
  description = "AWS ALB Target Group Name"
}

# =====================
# Code Build Env
# =====================

# https://www.terraform.io/docs/language/values/variables.html
variable "code_build_envs" {
  type = list(object({
    name : string,
    value : string
  }))
  default = []
}

variable "source_change_trigger" {
  type        = bool
  default     = true
  description = "檔案變更後執行 codepipeline"
}

variable "s3_version_control" {
  type        = string
  default     = "Enabled"
  description = "Versioning state of the bucket. Valid values: Enabled, Suspended, or Disabled. Disabled"
}