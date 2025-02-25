locals {
  aws_services = {
    Athena         = "Amazon Athena"
    EC2            = "Amazon Elastic Compute Cloud - Compute"
    ECR            = "Amazon EC2 Container Registry (ECR)"
    ECS            = "Amazon EC2 Container Service"
    Kubernetes     = "Amazon Elastic Container Service for Kubernetes"
    EBS            = "Amazon Elastic Block Store"
    CloudFront     = "Amazon CloudFront"
    CloudTrail     = "AWS CloudTrail"
    CloudWatch     = "AmazonCloudWatch"
    Cognito        = "Amazon Cognito"
    Config         = "AWS Config"
    DynamoDB       = "Amazon DynamoDB"
    DMS            = "AWS Database Migration Service"
    EFS            = "Amazon Elastic File System"
    ElastiCache    = "Amazon ElastiCache"
    Elasticsearch  = "Amazon Elasticsearch Service"
    ELB            = "Amazon Elastic Load Balancing"
    Gateway        = "Amazon API Gateway"
    Glue           = "AWS Glue"
    GuardDuty      = "Amazon GuardDuty"
    Kafka          = "Managed Streaming for Apache Kafka"
    KMS            = "AWS Key Management Service"
    Kinesis        = "Amazon Kinesis"
    Lambda         = "AWS Lambda"
    Lex            = "Amazon Lex"
    Matillion      = "Matillion ETL for Amazon Redshift"
    Pinpoint       = "AWS Pinpoint"
    Polly          = "Amazon Polly"
    Rekognition    = "Amazon Rekognition"
    RDS            = "Amazon Relational Database Service"
    Redshift       = "Amazon Redshift"
    S3             = "Amazon Simple Storage Service"
    SFTP           = "AWS Transfer for SFTP"
    Route53        = "Amazon Route 53"
    SageMaker      = "Amazon SageMaker"
    SecretsManager = "AWS Secrets Manager"
    SES            = "Amazon Simple Email Service"
    SNS            = "Amazon Simple Notification Service"
    SQS            = "Amazon Simple Queue Service"
    Tax            = "Tax"
    VPC            = "Amazon Virtual Private Cloud"
    WAF            = "AWS WAF"
    XRay           = "AWS X-Ray"
  }
}

resource "aws_sns_topic" "account_budgets_alarm_topic" {
  count = var.budget_alarm_sns_topic_arn == "" ? 1 : 0
  name = "${replace(lower(var.budget_name), "/[^a-z0-9_-]/", "_")}_budgets_alarm_topic"
  tags = var.tags
}

resource "aws_sns_topic_policy" "account_budgets_alarm_policy" {
  count = var.budget_alarm_sns_topic_arn == "" ? 1 : 0
  arn    = aws_sns_topic.account_budgets_alarm_topic[0].arn
  policy = data.aws_iam_policy_document.sns_topic_policy[0].json
}

data "aws_iam_policy_document" "sns_topic_policy" {
  count = var.budget_alarm_sns_topic_arn == "" ? 1 : 0
  statement {
    sid    = "AWSBudgetsSNSPublishingPermissions"
    effect = "Allow"

    actions = [
      "SNS:Receive",
      "SNS:Publish"
    ]

    principals {
      type        = "Service"
      identifiers = ["budgets.amazonaws.com"]
    }

    resources = [
      aws_sns_topic.account_budgets_alarm_topic[0].arn
    ]
  }
}

resource "aws_budgets_budget" "budget_account" {
  name              = "${var.budget_name}"
  budget_type       = "COST"
  limit_amount      = var.account_budget_limit
  limit_unit        = var.budget_limit_unit
  time_unit         = var.budget_time_unit
  time_period_start = "2020-01-01_00:00"

  cost_types {
    use_amortized = var.use_amortized
  }

  dynamic "notification" {
    for_each = var.notifications

    content {
      comparison_operator = notification.value.comparison_operator
      threshold           = notification.value.threshold
      threshold_type      = notification.value.threshold_type
      notification_type   = notification.value.notification_type
      subscriber_sns_topic_arns = [
        var.budget_alarm_sns_topic_arn != "" ? var.budget_alarm_sns_topic_arn : aws_sns_topic.account_budgets_alarm_topic[0].arn
      ]
    }
  }

  depends_on = [
    aws_sns_topic.account_budgets_alarm_topic
  ]
}

resource "aws_budgets_budget" "budget_resources" {
  for_each = var.services

  name              = "${var.budget_name} - ${each.key}"
  budget_type       = "COST"
  limit_amount      = each.value.budget_limit
  limit_unit        = var.budget_limit_unit
  time_unit         = var.budget_time_unit
  time_period_start = "2020-01-01_00:00"

  cost_types {
    use_amortized = var.use_amortized
  }

  cost_filters = {
    Service = lookup(local.aws_services, each.key)
  }

  dynamic "notification" {
    for_each = var.notifications

    content {
      comparison_operator = notification.value.comparison_operator
      threshold           = notification.value.threshold
      threshold_type      = notification.value.threshold_type
      notification_type   = notification.value.notification_type
      subscriber_sns_topic_arns = [
        var.budget_alarm_sns_topic_arn != "" ? var.budget_alarm_sns_topic_arn : aws_sns_topic.account_budgets_alarm_topic[0].arn
      ]
    }
  }

  depends_on = [
    aws_sns_topic.account_budgets_alarm_topic
  ]
}

data "local_file" "cloudformation_template" {
  filename = "${path.module}/cloudformation.yml"
}

resource "aws_iam_role" "chatbot_notification" {
  count = var.create_slack_integration == true ? 1 : 0

  name = "ChatBotNotificationRole"

  assume_role_policy = jsonencode({
    Version : "2012-10-17",
    Statement : [
      {
        Effect : "Allow",
        Principal : {
          Service : "chatbot.amazonaws.com"
        },
        Action : "sts:AssumeRole"
      }
    ]
  })
}

resource "aws_iam_role_policy" "chatbot_notification" {
  count = var.create_slack_integration == true ? 1 : 0

  name = "ChatBotNotificationPolicy"
  role = aws_iam_role.chatbot_notification[0].id

  policy = jsonencode({
    "Version" : "2012-10-17",
    "Statement" : [
      {
        Action : [
          "cloudwatch:Describe*",
          "cloudwatch:Get*",
          "cloudwatch:List*"
        ],
        Effect : "Allow",
        Resource : "*"
      }
    ]
  })
}

resource "aws_cloudformation_stack" "chatbot_slack_configuration" {
  count = var.create_slack_integration == true ? 1 : 0

  name = "chatbot-slack-budget-alarms"

  template_body = data.local_file.cloudformation_template.content

  parameters = {
    ConfigurationNameParameter = "budget-alarms"
    IamRoleArnParameter        = aws_iam_role.chatbot_notification[0].arn
    SlackChannelIdParameter    = var.slack_channel_id
    SlackWorkspaceIdParameter  = var.slack_workspace_id
    SnsTopicArnsParameter      = var.budget_alarm_sns_topic_arn != "" ? var.budget_alarm_sns_topic_arn : aws_sns_topic.account_budgets_alarm_topic[0].arn
  }

  tags = var.tags
}
