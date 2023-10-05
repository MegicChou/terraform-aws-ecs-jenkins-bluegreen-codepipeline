# Terraform module which creates CodePipeline for ECS resources on AWS.
#
# https://docs.aws.amazon.com/codepipeline/latest/userguide/welcome.html

# https://www.terraform.io/docs/providers/aws/r/codepipeline.html

resource "aws_s3_bucket" "default" {
  bucket = var.artifact_bucket_name
}

resource "aws_s3_bucket_ownership_controls" "default" {
  bucket = aws_s3_bucket.default.id
  rule {
    object_ownership = "BucketOwnerPreferred"
  }
}

resource "aws_s3_bucket_acl" "default" {
  depends_on = [aws_s3_bucket_ownership_controls.default]
  bucket     = aws_s3_bucket.default.id
  acl        = "private"
}

resource "aws_s3_bucket_versioning" "s3_default_version" {
  bucket = aws_s3_bucket.default.id
  versioning_configuration {
    status = var.s3_version_control
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "s3_lifecycle" {
  bucket = aws_s3_bucket.default.bucket

  rule {
    id     = "version-destroy"
    status = "Enabled"

    # 物件建立後幾天刪除
    expiration {
      days = 30
    }

    # 永久刪除非目前版本的物件
    noncurrent_version_expiration {
      # 物件成為非目前版本後的天數
      noncurrent_days = 7
    }
  }
}


resource "aws_codepipeline" "default" {
  name     = var.name
  role_arn = aws_iam_role.default.arn

  # The Amazon S3 bucket where artifacts are stored for the pipeline.
  # https://docs.aws.amazon.com/codepipeline/latest/APIReference/API_ArtifactStore.html
  artifact_store {
    # You can specify the name of an S3 bucket but not a folder within the bucket.
    # A folder to contain the pipeline artifacts is created for you based on the name of the pipeline.
    # You can use any Amazon S3 bucket in the same AWS Region as the pipeline to store your pipeline artifacts.
    location = aws_s3_bucket.default.bucket

    # The value must be set to S3.
    type = "S3"

    # The encryption key used to encrypt the data in the artifact store, such as an AWS KMS key.
    # If this is undefined, the default key for Amazon S3 is used.
    encryption_key {
      # The ID used to identify the key. For an AWS KMS key, this is the key ID or key ARN.
      id = var.encryption_key_id != "" ? var.encryption_key_id : data.aws_kms_alias.s3.arn

      # The value must be set to KMS.
      type = "KMS"
    }
  }

  # The pipeline structure has the following requirements:
  #
  # - A pipeline must contain at least two stages.
  # - The first stage of a pipeline must contain at least one source action, and can only contain source actions.
  # - Only the first stage of a pipeline may contain source actions.
  # - At least one stage in each pipeline must contain an action that is not a source action.
  # - All stage names within a pipeline must be unique.
  #
  # https://docs.aws.amazon.com/codepipeline/latest/userguide/reference-pipeline-structure.html
  stage {
    name = "Source"

    action {
      name             = "Source"
      category         = "Source"
      owner            = "AWS"
      provider         = "S3"
      version          = 1
      run_order        = 1
      output_artifacts = ["Source"]

      configuration = {
        S3Bucket             = aws_s3_bucket.default.bucket
        S3ObjectKey          = var.s3_source_object_key
        PollForSourceChanges = var.source_change_trigger
      }
    }
  }

  stage {
    name = "Build"

    action {
      name             = "Build"
      category         = "Build"
      owner            = "AWS"
      provider         = "CodeBuild"
      version          = 1
      run_order        = 1
      input_artifacts  = ["Source"]
      output_artifacts = ["Build"]

      configuration = {
        ProjectName = aws_codebuild_project.app_build.name

        # One of your input sources must be designated the PrimarySource. This source is the directory
        # where AWS CodeBuild looks for and runs your buildspec file. The keyword PrimarySource is used to
        # specify the primary source in the configuration section of the CodeBuild stage in the JSON file.
        # https://docs.aws.amazon.com/codebuild/latest/userguide/sample-pipeline-multi-input-output.html
        PrimarySource = "Source"
      }
    }
  }

  stage {
    name = "Deploy"

    action {
      name            = "Deploy"
      category        = "Deploy"
      owner           = "AWS"
      provider        = "CodeDeployToECS"
      version         = 1
      run_order       = 1
      input_artifacts = ["Build"]

      configuration = {
        //        ClusterName = "${var.cluster_name}"
        //        ServiceName = "${var.service_name}"

        # An image definitions document is a JSON file that describes your ECS container name and the image and tag.
        # You must generate an image definitions file to provide the CodePipeline job worker
        # with the ECS container and image identification to use for your pipeline’s deployment stage.
        # https://docs.aws.amazon.com/codepipeline/latest/userguide/pipelines-create.html#pipelines-create-image-definitions
        //        FileName = "${var.file_name}"aws_cloudwatch_log_group

        // 藍綠色部屬看這
        // @see https://docs.aws.amazon.com/zh_tw/codepipeline/latest/userguide/action-reference-ECSbluegreen.html
        ApplicationName                = "${aws_codedeploy_app.app_deploy.name}"
        DeploymentGroupName            = "${aws_codedeploy_deployment_group.app_deploy_group.app_name}"
        TaskDefinitionTemplateArtifact = "Build"
        TaskDefinitionTemplatePath     = "taskdef.json"
        AppSpecTemplateArtifact        = "Build"
        AppSpecTemplatePath            = "appspec.yaml"
        Image1ArtifactName             = "Build"
        Image1ContainerName            = "IMAGE1_NAME"
      }
    }
  }

  # Suppress that Github OAuth causing persistent changes.
  # https://github.com/terraform-providers/terraform-provider-aws/issues/2854
  lifecycle {
    //ignore_changes = all
    ignore_changes = [stage[0].action[0].configuration.OAuthToken]
  }
}

data "aws_kms_alias" "s3" {
  name = "alias/aws/s3"
}

# Webhook for GitHub Pipeline
#
# https://docs.aws.amazon.com/codepipeline/latest/userguide/pipelines-webhooks.html

# https://www.terraform.io/docs/providers/aws/r/codepipeline_webhook.html
#resource "aws_codepipeline_webhook" "default" {
#  name            = aws_codepipeline.default.name
#  target_pipeline = aws_codepipeline.default.name
#
#  # The name of the action in a pipeline you want to connect to the webhook.
#  # The action must be from the source (first) stage of the pipeline.
#  target_action = "Source"
#
#  # GITHUB_HMAC implements the authentication scheme described here: https://developer.github.com/webhooks/securing/
#  # https://docs.aws.amazon.com/codepipeline/latest/APIReference/API_WebhookDefinition.html#CodePipeline-Type-WebhookDefinition-authentication
#  authentication = "GITHUB_HMAC"
#
#  # Set the same value as Secret of GitHub.
#  #
#  # NOTE: This value will be a random character string consisting of 96 numeric characters
#  #       when you setup from the AWS Management Console.
#  #
#  # https://docs.aws.amazon.com/codepipeline/latest/APIReference/API_WebhookAuthConfiguration.html
#  authentication_configuration {
#    secret_token = local.secret_token
#  }
#
#  # The event criteria that specify when a webhook notification is sent to your URL.
#  # https://docs.aws.amazon.com/codepipeline/latest/APIReference/API_WebhookFilterRule.html
#  filter {
#    json_path    = var.filter_json_path
#    match_equals = var.filter_match_equals
#  }
#}




# https://www.terraform.io/docs/providers/random/r/id.html
resource "random_id" "secret_token" {
  keepers = {
    keeper = var.name
  }

  byte_length = 40
}

locals {
  secret_token = var.secret_token == "" ? random_id.secret_token.dec : var.secret_token
}

# CodePipeline Service Role
#
# https://docs.aws.amazon.com/codepipeline/latest/userguide/how-to-custom-role.html

# https://www.terraform.io/docs/providers/aws/r/iam_role.html
resource "aws_iam_role" "default" {
  name               = local.iam_name
  assume_role_policy = data.aws_iam_policy_document.assume_role_policy.json
  path               = var.iam_path
  description        = var.description
  tags               = merge(tomap({ "Name" = local.iam_name }), var.tags)
}

data "aws_iam_policy_document" "assume_role_policy" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["codepipeline.amazonaws.com"]
    }
  }
}

# https://www.terraform.io/docs/providers/aws/r/iam_policy.html
resource "aws_iam_policy" "default" {
  name        = local.iam_name
  policy      = data.aws_iam_policy_document.policy.json
  path        = var.iam_path
  description = var.description
}

data "aws_iam_policy_document" "policy" {
  statement {
    effect = "Allow"

    actions = [
      "s3:PutObject",
      "s3:GetObject",
      "s3:GetObjectVersion",
      "s3:GetBucketVersioning",
    ]

    resources = [
      "arn:aws:s3:::${aws_s3_bucket.default.bucket}",
      "arn:aws:s3:::${aws_s3_bucket.default.bucket}/*",
    ]
  }

  statement {
    effect = "Allow"

    actions = [
      "codebuild:BatchGetBuilds",
      "codebuild:StartBuild",
    ]

    resources = ["*"]
  }

  statement {
    effect = "Allow"

    actions = [
      "ecs:DescribeServices",
      "ecs:DescribeTaskDefinition",
      "ecs:DescribeTasks",
      "ecs:ListTasks",
      "ecs:RegisterTaskDefinition",
      "ecs:UpdateService",
    ]

    resources = ["*"]
  }

  // 這個要開 不然 codedeploy 會失敗
  statement {
    effect = "Allow"

    actions = [
      "codedeploy:*"
    ]

    resources = ["*"]
  }

  statement {
    effect = "Allow"

    actions = [
      "iam:PassRole",
    ]

    resources = ["*"]
  }
}

# https://www.terraform.io/docs/providers/aws/r/iam_role_policy_attachment.html
resource "aws_iam_role_policy_attachment" "default" {
  role       = aws_iam_role.default.name
  policy_arn = aws_iam_policy.default.arn
}

locals {
  iam_name = "${var.name}-codepipeline"
}
