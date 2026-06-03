// Create VPC
module "vpc" {
  source    = "github.com/silinternational/terraform-modules//aws/vpc-public-only?ref=7.2.0"
  app_name  = var.app_name
  app_env   = var.app_env
  aws_zones = var.aws_zones
}

// Create ecs cluster
module "ecscluster" {
  source   = "github.com/silinternational/terraform-modules//aws/ecs/cluster?ref=7.2.0"
  app_name = var.app_name
  app_env  = var.app_env
}

// Create security group that allows 3306 from specific IPs
resource "aws_security_group" "db_access_limited_ips" {
  name        = "db-limited-ips"
  description = "Allow MySQL traffic from limited IPs"
  vpc_id      = module.vpc.id
}
resource "aws_security_group_rule" "mysql" {
  count             = var.db_access_enabled == "true" ? 1 : 0
  type              = "ingress"
  from_port         = 3306
  to_port           = 3306
  protocol          = "tcp"
  security_group_id = aws_security_group.db_access_limited_ips.id
  cidr_blocks       = toset(var.db_access_ips)
}

resource "aws_security_group_rule" "postgres" {
  count             = var.db_access_enabled == "true" ? 1 : 0
  type              = "ingress"
  from_port         = 5432
  to_port           = 5432
  protocol          = "tcp"
  security_group_id = aws_security_group.db_access_limited_ips.id
  cidr_blocks       = toset(var.db_access_ips)
}

// Create database and root passwords
resource "random_id" "db_admin_root_pass" {
  byte_length = 16
}

// Create shared RDS instance for BuildEngine and Portal (if deployed)
resource "aws_db_instance" "db_instance" {
  engine                  = "postgres"
  engine_version          = "17.9"
  port                    = 5432
  identifier              = "${var.app_name}-${var.app_env}"
  instance_class          = var.db_instance_class
  allocated_storage       = var.db_storage
  backup_retention_period = var.db_backup_retention_period
  publicly_accessible     = true
  multi_az                = var.db_multi_az
  db_name                 = var.buildengine_db_name
  username                = var.db_admin_root_user
  password                = random_id.db_admin_root_pass.hex
  vpc_security_group_ids  = [module.vpc.vpc_default_sg_id, aws_security_group.db_access_limited_ips.id]
  db_subnet_group_name    = module.vpc.db_subnet_group_name
  availability_zone       = var.aws_zones[0]
}

// Determine most recent ECS optimized AMI
data "aws_ami" "ecs_ami" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-ecs-hvm-*-x86_64"]
  }
}

// Create security group that allows 22 from specific IPs
resource "aws_security_group" "ec2_ssh_limited_ips" {
  name        = "ssh-limited-ips"
  description = "Allow SSH traffic from limited IPs"
  vpc_id      = module.vpc.id
}

resource "aws_security_group_rule" "ssh" {
  count             = var.ssh_enabled == "true" ? 1 : 0
  type              = "ingress"
  from_port         = 22
  to_port           = 22
  protocol          = "tcp"
  security_group_id = aws_security_group.ec2_ssh_limited_ips.id
  cidr_blocks       = toset(var.ssh_ips)
}

// Create EC2 host for ECS cluster
resource "aws_instance" "ecshost" {
  ami                    = data.aws_ami.ecs_ami.id
  instance_type          = var.aws_instance["instance_type"]
  key_name               = var.ec2_ssh_key_name
  vpc_security_group_ids = [module.vpc.vpc_default_sg_id, aws_security_group.ec2_ssh_limited_ips.id]
  iam_instance_profile   = module.ecscluster.ecs_instance_profile_id
  user_data              = templatefile("${path.module}/user-data.sh", { ecs_cluster_name = module.ecscluster.ecs_cluster_name })
  subnet_id              = module.vpc.public_subnet_ids[0]

  root_block_device {
    volume_size = var.aws_instance["volume_size"]
  }

  tags = {
    Name        = var.tag_name
    app         = var.tag_app
    environment = var.tag_environment
    project     = var.tag_project
    scheduler   = var.tag_scheduler
    running     = var.tag_scheduler_running
  }
}

resource "aws_eip" "public" {
  instance = aws_instance.ecshost.id

  tags = {
    app         = var.tag_app
    environment = var.tag_environment
    project     = var.tag_project
  }
}

// Get ssl cert for use with listener
data "aws_acm_certificate" "appbuilder" {
  domain = var.cert_domain_name
}

// Create security group that allows 443 from specific IPs
resource "aws_security_group" "alb_https_limited_ips" {
  name        = "https-limited-ips"
  description = "Allow HTTPS traffic from limited IPs"
  vpc_id      = module.vpc.id
}

resource "aws_security_group_rule" "limited_buildengine" {
  type              = "ingress"
  from_port         = 8443
  to_port           = 8443
  protocol          = "tcp"
  security_group_id = aws_security_group.alb_https_limited_ips.id
  cidr_blocks       = contains(var.https_ips, "0.0.0.0/0") ? ["0.0.0.0/0"] : toset(concat(var.https_ips, ["${aws_eip.public.public_ip}/32"]))
}

// Create application load balancer for public access
module "alb" {
  source          = "github.com/silinternational/terraform-modules//aws/alb?ref=7.2.0"
  app_name        = var.app_name
  app_env         = var.app_env
  internal        = "false"
  vpc_id          = module.vpc.id
  security_groups = [module.vpc.vpc_default_sg_id, aws_security_group.alb_https_limited_ips.id, module.cloudflare-sg.id]
  subnets         = module.vpc.public_subnet_ids
  certificate_arn = data.aws_acm_certificate.appbuilder.arn
  port            = "6173"
  tg_name         = "tg-${var.app_name}-${var.app_env}-portal"
}

resource "aws_alb_listener" "buildengine" {
  default_action {
    target_group_arn = aws_alb_target_group.buildengine.arn
    type             = "forward"
  }

  load_balancer_arn = module.alb.arn
  port              = 8443
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-2016-08"
  certificate_arn   = data.aws_acm_certificate.appbuilder.arn
}

// Create BuildEngine Target Group
resource "aws_alb_target_group" "buildengine" {
  name_prefix          = substr("be-${var.app_env}-", 0, 6)
  port                 = "8443"
  protocol             = "HTTP"
  vpc_id               = module.vpc.id
  deregistration_delay = "30"

  health_check {
    path                = "/health"
    protocol            = "HTTP"
    port                = "traffic-port"
    healthy_threshold   = 5
    unhealthy_threshold = 2
    timeout             = 5
    interval            = 30
  }

  stickiness {
    type = "lb_cookie"
  }

  lifecycle {
    create_before_destroy = true
  }
}


// Artifacts stuff - S3, IAM
// Use "files" insteads of "artifacts" for user facing bucket name
resource "aws_s3_bucket" "artifacts" {
  bucket = "${var.org_prefix}-${var.app_env}-${var.app_name}-files"
  //policy        = data.template_file.artifacts_bucket_policy.rendered
  force_destroy = true

  tags = {
    app         = var.tag_app
    environment = var.tag_environment
    project     = var.tag_project
  }
}

resource "aws_s3_bucket_policy" "artifacts" {
  depends_on = [aws_s3_bucket_public_access_block.artifacts]

  bucket = aws_s3_bucket.artifacts.id
  policy = data.aws_iam_policy_document.artifacts.json
}

data "aws_iam_policy_document" "artifacts" {
  statement {
    sid    = "PublicReadGetObject"
    effect = "Allow"
    principals {
      type        = "*"
      identifiers = ["*"]
    }
    actions   = ["s3:GetObject"]
    resources = ["${aws_s3_bucket.artifacts.arn}/*"]
  }
}

resource "aws_s3_bucket_website_configuration" "artifacts" {
  bucket = aws_s3_bucket.artifacts.id

  index_document {
    suffix = "index.html"
  }

  error_document {
    key = "error.html"
  }
}

resource "aws_s3_bucket_ownership_controls" "artifacts" {
  bucket = aws_s3_bucket.artifacts.id
  rule {
    object_ownership = "BucketOwnerPreferred"
  }
}

resource "aws_s3_bucket_public_access_block" "artifacts" {
  bucket = aws_s3_bucket.artifacts.id

  block_public_acls       = false
  block_public_policy     = false
  ignore_public_acls      = false
  restrict_public_buckets = false
}

resource "aws_s3_bucket_acl" "artifacts" {
  depends_on = [
    aws_s3_bucket_ownership_controls.artifacts,
    aws_s3_bucket_public_access_block.artifacts,
  ]

  bucket = aws_s3_bucket.artifacts.id
  acl    = "public-read"
}

resource "aws_iam_policy" "artifacts" {
  name        = "s3-appbuilder-artifacts-${var.app_env}"
  description = "S3 App Builder Artifacts - write and delete build artifiacts accessed by end user"

  policy = <<EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "*"
            ],
            "Resource": [
                "${aws_s3_bucket.artifacts.arn}"
            ]
        },
        {
            "Effect": "Allow",
            "Action": [
                "*"
            ],
            "Resource": [
                "${aws_s3_bucket.artifacts.arn}/*"
            ]
        }
    ]
}
EOF

}

// Secrets stuff - S3, IAM
resource "aws_s3_bucket" "secrets" {
  bucket        = "${var.org_prefix}-${var.app_env}-${var.app_name}-secrets"
  force_destroy = true

  tags = {
    app         = var.tag_app
    environment = var.tag_environment
    project     = var.tag_project
  }
}

resource "aws_s3_bucket_ownership_controls" "secrets" {
  bucket = aws_s3_bucket.secrets.id
  rule {
    object_ownership = "BucketOwnerPreferred"
  }
}

resource "aws_s3_bucket_versioning" "secrets" {
  bucket = aws_s3_bucket.secrets.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_acl" "secrets" {
  depends_on = [aws_s3_bucket_ownership_controls.secrets]

  bucket = aws_s3_bucket.secrets.id
  acl    = "private"
}

resource "aws_s3_bucket_lifecycle_configuration" "secrets" {
  bucket = aws_s3_bucket.secrets.id

  rule {
    id     = "delete-old-versions"
    status = "Enabled"

    noncurrent_version_expiration {
      noncurrent_days = 30
    }
  }
}

resource "aws_iam_policy" "secrets" {
  name        = "s3-appbuilder-secrets-${var.app_env}"
  description = "S3 App Builder Secrets - extract ssh keys to access Git repository for Job DSL configuration"

  policy = <<EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "s3:GetBucketLocation",
                "s3:ListBucket"
            ],
            "Resource": [
                "${aws_s3_bucket.secrets.arn}"
            ]
        },
        {
            "Effect": "Allow",
            "Action": [
                "s3:GetObject"
            ],
            "Resource": [
                "${aws_s3_bucket.secrets.arn}/*"
            ]
        }
    ]
}
EOF

}

// Projects stuff - S3, IAM
resource "aws_s3_bucket" "projects" {
  bucket        = "${var.org_prefix}-${var.app_env}-${var.app_name}-projects"
  force_destroy = true

  tags = {
    app         = var.tag_app
    environment = var.tag_environment
    project     = var.tag_project
  }
}

resource "aws_s3_bucket_ownership_controls" "projects" {
  bucket = aws_s3_bucket.projects.id
  rule {
    object_ownership = "BucketOwnerPreferred"
  }
}

resource "aws_s3_bucket_versioning" "projects" {
  bucket = aws_s3_bucket.projects.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_acl" "projects" {
  depends_on = [aws_s3_bucket_ownership_controls.projects]

  bucket = aws_s3_bucket.projects.id
  acl    = "private"
}

resource "aws_s3_bucket_lifecycle_configuration" "projects" {
  bucket = aws_s3_bucket.projects.id

  rule {
    id     = "delete-really-old-versions"
    status = "Enabled"

    noncurrent_version_expiration {
      noncurrent_days = 365
    }
  }
}

resource "aws_iam_policy" "projects" {
  name        = "s3-appbuilder-projects-${var.app_env}"
  description = "S3 App Builder Projects"

  policy = <<EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "*"
            ],
            "Resource": [
                "${aws_s3_bucket.projects.arn}"
            ]
        },
        {
            "Effect": "Allow",
            "Action": [
                "*"
            ],
            "Resource": [
                "${aws_s3_bucket.projects.arn}/*"
            ]
        }
    ]
}
EOF

}

resource "aws_iam_policy" "ssm_parameters" {
  name        = "ssm-parameters-${var.app_env}"
  description = "Allow access to SSM parameters for ECS instances"

  policy = <<EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "ssm:GetParameters",
                "ssm:GetParameter"
            ],
            "Resource": "*"
        }
    ]
}
EOF

}

resource "aws_iam_policy" "project_creation_and_building" {
  name        = "project-creation-and-building-${var.app_env}"
  description = "Create Projects and Roles needed for building"

  policy = <<EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Sid": "VisualEditor0",
            "Effect": "Allow",
            "Action": [
                "iam:CreateGroup",
                "iam:AddUserToGroup",
                "iam:RemoveUserFromGroup",
                "iam:ListSSHPublicKeys",
                "iam:GetSSHPublicKey",
                "iam:UploadSSHPublicKey",
                "iam:GetUser",
                "iam:CreateUser",
                "iam:GetGroup",
                "iam:PutGroupPolicy",
		            "iam:GetRole",
                "iam:CreateRole",
                "iam:AttachRolePolicy",
                "iam:PassRole",
                "sts:GetFederationToken",
                "codebuild:CreateProject",
                "codebuild:BatchGetProjects",
                "codebuild:BatchGetBuilds",
                "codebuild:StartBuild",
                "ecr:DescribeImages",
                "ecr:DescribeRepositories",
                "ecr:BatchGetImage",
                "ecr:GetDownloadUrlForLayer"
            ],
            "Resource": "*"
        }
    ]
}
EOF

}

resource "aws_iam_policy" "codebuild-basepolicy-build" {
  name        = "codebuild-basepolicy-build_app-${var.app_env}"
  description = "CodeBuild base policy for building"

  policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Resource": [
        "arn:aws:logs:${var.aws_region}:${var.aws_account_id}:log-group:/aws/codebuild/build_app-${var.app_env}",
        "arn:aws:logs:${var.aws_region}:${var.aws_account_id}:log-group:/aws/codebuild/build_app-${var.app_env}:*"
      ],
      "Action": [
        "logs:CreateLogGroup",
        "logs:CreateLogStream",
        "logs:PutLogEvents"
      ]
    },
    {
      "Effect": "Allow",
      "Resource": [
        "arn:aws:s3:::codepipeline-${var.aws_region}-*"
      ],
      "Action": [
        "s3:PutObject",
        "s3:GetObject",
        "s3:GetObjectVersion"
      ]
    }
  ]
}
EOF

}

resource "aws_iam_policy" "codebuild-basepolicy-publish" {
  name        = "codebuild-basepolicy-publish_app-${var.app_env}"
  description = "CodeBuild base policy for publishing"

  policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Resource": [
        "arn:aws:logs:${var.aws_region}:${var.aws_account_id}:log-group:/aws/codebuild/publish_app-${var.app_env}",
        "arn:aws:logs:${var.aws_region}:${var.aws_account_id}:log-group:/aws/codebuild/publish_app-${var.app_env}:*"
      ],
      "Action": [
        "logs:CreateLogGroup",
        "logs:CreateLogStream",
        "logs:PutLogEvents"
      ]
    },
    {
      "Effect": "Allow",
      "Resource": [
        "arn:aws:s3:::codepipeline-${var.aws_region}-*"
      ],
      "Action": [
        "s3:PutObject",
        "s3:GetObject",
        "s3:GetObjectVersion"
      ]
    }
  ]
}
EOF

}

resource "aws_iam_role" "codebuild-build_app-service-role" {
  name = "codebuild-build_app-service-role-${var.app_env}"

  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "codebuild.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
EOF

}

resource "aws_iam_role_policy_attachment" "build-s3-secrets" {
  policy_arn = aws_iam_policy.secrets.arn
  role       = aws_iam_role.codebuild-build_app-service-role.name
}

resource "aws_iam_role_policy_attachment" "build-s3-artifacts" {
  policy_arn = aws_iam_policy.artifacts.arn
  role       = aws_iam_role.codebuild-build_app-service-role.name
}

resource "aws_iam_role_policy_attachment" "build-s3-projects" {
  policy_arn = aws_iam_policy.projects.arn
  role       = aws_iam_role.codebuild-build_app-service-role.name
}

resource "aws_iam_role_policy_attachment" "build-codebuild-basepolicy" {
  policy_arn = aws_iam_policy.codebuild-basepolicy-build.arn
  role       = aws_iam_role.codebuild-build_app-service-role.name
}

resource "aws_iam_role" "codebuild-publish_app-service-role" {
  name = "codebuild-publish_app-service-role-${var.app_env}"

  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "codebuild.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
EOF

}

resource "aws_iam_role_policy_attachment" "publish-s3-secrets" {
  policy_arn = aws_iam_policy.secrets.arn
  role       = aws_iam_role.codebuild-publish_app-service-role.name
}

resource "aws_iam_role_policy_attachment" "publish-s3-artifacts" {
  policy_arn = aws_iam_policy.artifacts.arn
  role       = aws_iam_role.codebuild-publish_app-service-role.name
}

resource "aws_iam_role_policy_attachment" "publish-s3-projects" {
  policy_arn = aws_iam_policy.projects.arn
  role       = aws_iam_role.codebuild-publish_app-service-role.name
}

resource "aws_iam_role_policy_attachment" "publish-codebuild-basepolicy" {
  policy_arn = aws_iam_policy.codebuild-basepolicy-publish.arn
  role       = aws_iam_role.codebuild-publish_app-service-role.name
}

// Attach SSM policy to ECS instance role
resource "aws_iam_role_policy_attachment" "ecs-instance-ssm" {
  policy_arn = aws_iam_policy.ssm_parameters.arn
  role       = module.ecscluster.ecs_instance_role_id
}

// Create appbuilder IAM user, policy attachments
resource "aws_iam_user" "appbuilder" {
  name = "appbuilder-${var.app_env}"
}

resource "aws_iam_access_key" "appbuilder" {
  user = aws_iam_user.appbuilder.name
}

resource "aws_iam_user_policy_attachment" "appbuilder-artifacts" {
  user       = aws_iam_user.appbuilder.name
  policy_arn = aws_iam_policy.artifacts.arn
}

resource "aws_iam_user_policy_attachment" "appbuilder-secrets" {
  user       = aws_iam_user.appbuilder.name
  policy_arn = aws_iam_policy.secrets.arn
}

// Create buildengine IAM user, policy attachments
resource "aws_iam_user" "buildengine" {
  name = "buildengine-${var.app_env}"
}

resource "aws_iam_access_key" "buildengine" {
  user = aws_iam_user.buildengine.name
}

resource "aws_iam_user_policy_attachment" "buildengine-artifacts" {
  user       = aws_iam_user.buildengine.name
  policy_arn = aws_iam_policy.artifacts.arn
}

resource "aws_iam_user_policy_attachment" "buildengine-secrets" {
  user       = aws_iam_user.buildengine.name
  policy_arn = aws_iam_policy.secrets.arn
}

resource "aws_iam_user_policy_attachment" "buildengine-projects" {
  user       = aws_iam_user.buildengine.name
  policy_arn = aws_iam_policy.projects.arn
}

resource "aws_iam_user_policy_attachment" "buildengine-project-creation" {
  user       = aws_iam_user.buildengine.name
  policy_arn = aws_iam_policy.project_creation_and_building.arn
}

// Create ECS service for buildengine
resource "random_id" "api_access_token" {
  byte_length = 16
}

resource "random_id" "front_cookie_key" {
  byte_length = 16
}

// Create ECR Repo for Build Agent
resource "aws_ecr_repository" "agent" {
  name = "${var.buildagent_code_build_image_repo}-${var.app_env}"
}

resource "aws_ecr_lifecycle_policy" "agent" {
  repository = aws_ecr_repository.agent.name

  policy = <<EOF
{
    "rules": [
        {
            "rulePriority": 1,
            "description": "Keep 3 Latest",
            "selection": {
                "tagStatus": "any",
                "countType": "imageCountMoreThan",
                "countNumber": 3
            },
            "action": {
                "type": "expire"
            }
        }
    ]
}
EOF
}

resource "aws_ecr_repository_policy" "agent" {
  repository = aws_ecr_repository.agent.name

  policy = <<EOF
{
  "Version": "2008-10-17",
  "Statement": [
    {
      "Sid": "CodeBuildAccess",
      "Effect": "Allow",
      "Principal": {
        "Service": "codebuild.amazonaws.com"
      },
      "Action": [
        "ecr:BatchCheckLayerAvailability",
        "ecr:BatchGetImage",
        "ecr:GetDownloadUrlForLayer"
      ]
    }
  ]
}
EOF
}

// Create ECR Repo for BuildEngine API
resource "aws_ecr_repository" "buildengine_api" {
  name = var.buildengine_docker_image
}

resource "aws_ecr_lifecycle_policy" "buildengine_api" {
  repository = aws_ecr_repository.buildengine_api.name

  policy = <<EOF
{
  "rules": [
    {
      "rulePriority": 1,
      "description": "Keep 6 Latest",
      "selection": {
        "tagStatus": "any",
        "countType": "imageCountMoreThan",
        "countNumber": 6
      },
      "action": {
        "type": "expire"
      }
    }
  ]
}
EOF
}

resource "aws_codebuild_project" "build" {
  name           = "build_app-${var.app_env}"
  service_role   = aws_iam_role.codebuild-build_app-service-role.arn
  build_timeout  = 60
  queued_timeout = 480
  encryption_key = "arn:aws:kms:${var.aws_region}:${var.aws_account_id}:alias/aws/s3"
  badge_enabled  = false

  source {
    type      = "NO_SOURCE"
    buildspec = "version: 0.2"
  }

  artifacts {
    type                = "S3"
    location            = aws_s3_bucket.artifacts.bucket
    path                = "codebuild-output"
    namespace_type      = "NONE"
    name                = "/"
    packaging           = "NONE"
    encryption_disabled = false
  }

  cache {
    type  = "LOCAL"
    modes = ["LOCAL_DOCKER_LAYER_CACHE"]
  }

  environment {
    compute_type                = "BUILD_GENERAL1_SMALL"
    image                       = "${var.aws_account_id}.dkr.ecr.${var.aws_region}.amazonaws.com/${var.buildagent_code_build_image_repo}-${var.app_env}:${var.buildagent_code_build_image_tag}"
    type                        = "LINUX_CONTAINER"
    privileged_mode             = true // needed for LOCAL_DOCKER_LAYER_CACHE
    image_pull_credentials_type = "CODEBUILD"
  }
}

resource "aws_codebuild_project" "publish" {
  name           = "publish_app-${var.app_env}"
  service_role   = aws_iam_role.codebuild-publish_app-service-role.arn
  build_timeout  = 60
  queued_timeout = 480
  encryption_key = "arn:aws:kms:${var.aws_region}:${var.aws_account_id}:alias/aws/s3"
  badge_enabled  = false

  source {
    type      = "NO_SOURCE"
    buildspec = "version: 0.2"
  }

  artifacts {
    type                = "S3"
    location            = aws_s3_bucket.artifacts.bucket
    path                = "codebuild-output"
    namespace_type      = "NONE"
    name                = "/"
    packaging           = "NONE"
    encryption_disabled = false
  }

  cache {
    type  = "LOCAL"
    modes = ["LOCAL_DOCKER_LAYER_CACHE"]
  }

  environment {
    compute_type                = "BUILD_GENERAL1_SMALL"
    image                       = "${var.aws_account_id}.dkr.ecr.${var.aws_region}.amazonaws.com/${var.buildagent_code_build_image_repo}-${var.app_env}:${var.buildagent_code_build_image_tag}"
    type                        = "LINUX_CONTAINER"
    privileged_mode             = true
    image_pull_credentials_type = "CODEBUILD"
  }
}

// Uses default target group to route all https/443 traffic to buildengine
module "ecsservice_buildengine" {
  source       = "github.com/silinternational/terraform-modules//aws/ecs/service-only?ref=7.2.0"
  cluster_id   = module.ecscluster.ecs_cluster_id
  service_name = "buildengine"
  service_env  = var.app_env
  container_def_json = templatefile("${path.module}/task-def-buildengine.json", {
    buildengine_cpu                      = var.buildengine_cpu
    buildengine_memory                   = var.buildengine_memory
    buildengine_docker_image             = "${var.aws_account_id}.dkr.ecr.${var.aws_region}.amazonaws.com/${var.buildengine_docker_image}"
    buildengine_docker_tag               = var.buildengine_docker_tag
    buildengine_otel_docker_image        = "${var.aws_account_id}.dkr.ecr.${var.aws_region}.amazonaws.com/${var.buildengine_otel_docker_image}"
    buildengine_otel_docker_tag          = var.buildengine_otel_docker_tag
    API_ACCESS_TOKEN                     = random_id.api_access_token.hex
    APP_ENV                              = var.app_env
    AUTH0_SECRET                         = var.deploy_portal ? random_id.auth0_secret[0].hex : var.scriptoria_auth0_secret
    AWS_ACCESS_KEY_ID                    = aws_iam_access_key.buildengine.id
    AWS_SECRET_ACCESS_KEY                = aws_iam_access_key.buildengine.secret
    AWS_USER_ID                          = var.aws_account_id
    BUILD_ENGINE_ARTIFACTS_BUCKET        = aws_s3_bucket.artifacts.bucket
    BUILD_ENGINE_ARTIFACTS_BUCKET_REGION = var.aws_region
    BUILD_ENGINE_PROJECTS_BUCKET         = aws_s3_bucket.projects.bucket
    BUILD_ENGINE_SECRETS_BUCKET          = aws_s3_bucket.secrets.bucket
    CODE_BUILD_IMAGE_REPO                = "${var.aws_account_id}.dkr.ecr.${var.aws_region}.amazonaws.com/${var.buildagent_code_build_image_repo}-${var.app_env}"
    CODE_BUILD_IMAGE_TAG                 = var.buildagent_code_build_image_tag
    DATABASE_URL                         = "postgres://${var.db_admin_root_user}:${random_id.db_admin_root_pass.hex}@${aws_db_instance.db_instance.address}/${var.buildengine_db_name}?schema=public"
    HONEYCOMB_API_KEY                    = var.honeycomb_api_key
    ORIGIN                               = "https://${var.app_sub_domain}-buildengine.${var.cloudflare_domain}:8443"
    otel_cpu                             = var.otel_cpu
    otel_memory                          = var.otel_memory
    otel_docker_image                    = "${var.aws_account_id}.dkr.ecr.${var.aws_region}.amazonaws.com/${var.otel_docker_image}"
    otel_docker_tag                      = var.otel_docker_tag
    PUBLIC_SCRIPTORIA_URL                = var.deploy_portal ? "https://${var.app_sub_domain}.${var.cloudflare_domain}" : var.scriptoria_url
    SCRIPTURE_EARTH_KEY                  = var.scripture_earth_key
    VALKEY_HOST                          = aws_elasticache_replication_group.valkey[0].primary_endpoint_address
  })
  desired_count      = 1
  tg_arn             = aws_alb_target_group.buildengine.arn
  lb_container_name  = "buildengine"
  lb_container_port  = 8443
  ecsServiceRole_arn = module.ecscluster.ecsServiceRole_arn
}

// portal components

resource "aws_iam_policy" "email-notification" {
  count       = var.deploy_portal ? 1 : 0
  name        = "email-notification-${var.app_name}-${var.app_env}"
  description = "Send email notifications for events in Scriptoria"

  policy = <<EOF
{
    "Version":"2012-10-17",
    "Statement":[
        {
            "Effect":"Allow",
            "Action":[
                "ses:SendEmail",
                "ses:SendRawEmail"
            ],
            "Resource":"*",
            "Condition":{
                "StringEquals":{
                    "ses:FromAddress":"${var.admin_email}",
                    "ses:FromDisplayName":"${var.admin_name}"
                }
            }
        }
    ]
}
EOF

}

resource "aws_iam_user" "portal" {
  count = var.deploy_portal ? 1 : 0
  name  = "appbuilder-portal-${var.app_env}"
}

resource "aws_iam_access_key" "portal" {
  count = var.deploy_portal ? 1 : 0
  user  = aws_iam_user.portal[0].name
}

resource "aws_iam_user_policy_attachment" "appbuilder-portal-email" {
  count      = var.deploy_portal ? 1 : 0
  user       = aws_iam_user.portal[0].name
  policy_arn = aws_iam_policy.email-notification[0].arn
}

// Create security group for Valkey access
resource "aws_security_group" "valkey_access" {
  count       = 1 // With BE2, it is always needed
  name        = "valkey-access-${var.app_env}"
  description = "Allow Valkey traffic from application"
  vpc_id      = module.vpc.id

  ingress {
    from_port       = var.valkey_port
    to_port         = var.valkey_port
    protocol        = "tcp"
    security_groups = [module.vpc.vpc_default_sg_id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name        = "valkey-access-${var.app_env}"
    app         = var.tag_app
    environment = var.tag_environment
    project     = var.tag_project
  }
}

// Create Valkey subnet group
resource "aws_elasticache_subnet_group" "valkey" {
  count      = 1 // With BE2, it is always needed
  name       = "valkey-subnet-group-${var.app_env}"
  subnet_ids = module.vpc.public_subnet_ids
}

// Create Valkey parameter group with noeviction policy
resource "aws_elasticache_parameter_group" "valkey" {
  count  = 1 // With BE2, it is always needed
  name   = "valkey-params-${var.app_env}"
  family = "redis7"

  parameter {
    name  = "maxmemory-policy"
    value = "noeviction"
  }
}

// Create Valkey replication group (uses Valkey engine in ElastiCache)
resource "aws_elasticache_replication_group" "valkey" {
  count                      = 1 // With BE2, it is always needed
  replication_group_id       = "valkey-${var.app_env}"
  description                = "Valkey (Redis-compatible) cache for ${var.app_env}"
  engine                     = "redis"
  engine_version             = var.valkey_engine_version
  node_type                  = var.valkey_node_type
  num_cache_clusters         = var.valkey_num_cache_nodes
  parameter_group_name       = aws_elasticache_parameter_group.valkey[0].name
  port                       = var.valkey_port
  subnet_group_name          = aws_elasticache_subnet_group.valkey[0].name
  security_group_ids         = [aws_security_group.valkey_access[0].id]
  automatic_failover_enabled = var.valkey_num_cache_nodes > 1 ? true : false
  // multi_az_enabled may require specific AZ configs; omit unless needed

  tags = {
    Name        = "valkey-${var.app_env}"
    app         = var.tag_app
    environment = var.tag_environment
    project     = var.tag_project
  }
}

resource "random_id" "auth0_secret" {
  count       = var.deploy_portal ? 1 : 0
  byte_length = 32
}

// Uses default target group to route all https/443 traffic to buildengine
module "ecsservice_portal" {
  count        = var.deploy_portal ? 1 : 0
  source       = "github.com/silinternational/terraform-modules//aws/ecs/service-only?ref=7.2.0"
  cluster_id   = module.ecscluster.ecs_cluster_id
  service_name = "portal"
  service_env  = var.app_env
  container_def_json = templatefile("${path.module}/task-def-portal.json", {
    ADMIN_EMAIL                          = var.admin_email
    ADMIN_NAME                           = var.admin_name
    APP_ENV                              = var.app_env
    AUTH0_CLIENT_ID                      = var.auth0_client_id
    AUTH0_CLIENT_SECRET                  = var.auth0_client_secret
    AUTH0_CONNECTION                     = var.auth0_connection
    AUTH0_DOMAIN                         = var.auth0_domain
    AUTH0_SECRET                         = random_id.auth0_secret[0].hex
    AWS_EMAIL_ACCESS_KEY_ID              = aws_iam_access_key.portal[0].id
    AWS_EMAIL_SECRET_ACCESS_KEY          = aws_iam_access_key.portal[0].secret
    AWS_REGION                           = var.aws_region
    DATABASE_URL                         = "postgres://${var.db_admin_root_user}:${random_id.db_admin_root_pass.hex}@${aws_db_instance.db_instance.address}/${var.portal_db_name}?schema=public"
    DEFAULT_BUILDENGINE_URL              = "https://${cloudflare_record.buildengine.hostname}:8443"
    DEFAULT_BUILDENGINE_API_ACCESS_TOKEN = random_id.api_access_token.hex
    MAIL_SENDER                          = var.mail_sender
    ORIGIN                               = "https://${var.app_sub_domain}.${var.cloudflare_domain}"
    portal_cpu                           = var.portal_cpu
    portal_memory                        = var.portal_memory
    portal_docker_image                  = "${var.aws_account_id}.dkr.ecr.${var.aws_region}.amazonaws.com/${var.portal_docker_image}"
    portal_docker_tag                    = var.portal_docker_tag
    otel_cpu                             = var.otel_cpu
    otel_memory                          = var.otel_memory
    otel_docker_image                    = "${var.aws_account_id}.dkr.ecr.${var.aws_region}.amazonaws.com/${var.otel_docker_image}"
    otel_docker_tag                      = var.otel_docker_tag
    SPARKPOST_API_KEY                    = var.sparkpost_api_key
    VALKEY_HOST                          = aws_elasticache_replication_group.valkey[0].primary_endpoint_address
    HONEYCOMB_API_KEY                    = var.honeycomb_api_key
  })
  desired_count      = 1
  tg_arn             = module.alb.default_tg_arn
  lb_container_name  = "origin"
  lb_container_port  = 6173
  ecsServiceRole_arn = module.ecscluster.ecsServiceRole_arn
}

// Create DNS CNAME record on Cloudflare
data "cloudflare_zone" "domain" {
  name = var.cloudflare_domain
}

resource "cloudflare_record" "buildengine" {
  zone_id = data.cloudflare_zone.domain.id
  name    = "${var.app_sub_domain}-buildengine"
  type    = "CNAME"
  content = module.alb.dns_name
  proxied = false
}

// Portal DNS record
data "cloudflare_zone" "portal" {
  count = var.deploy_portal ? 1 : 0
  name  = var.cloudflare_domain
}

resource "cloudflare_record" "app_ui" {
  count   = var.deploy_portal ? 1 : 0
  zone_id = data.cloudflare_zone.portal[0].id
  name    = var.app_sub_domain
  type    = "CNAME"
  content = module.alb.dns_name
  proxied = true
}

// Security group to limit traffic to Cloudflare IPs
module "cloudflare-sg" {
  source = "github.com/silinternational/terraform-modules//aws/cloudflare-sg?ref=7.2.0"
  vpc_id = module.vpc.id
}

resource "aws_iam_role" "lambda_exec" {
  name = "${var.app_name}-grader-lambda-${var.app_env}-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "lambda_basic" {
  role       = aws_iam_role.lambda_exec.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role_policy_attachment" "lambda_vpc_access" {
  role       = aws_iam_role.lambda_exec.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaVPCAccessExecutionRole"
}

resource "aws_iam_role" "projects_s3files" {
  name = "${var.app_name}-projects-s3files-${var.app_env}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid    = "AllowS3FilesAssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "elasticfilesystem.amazonaws.com"
      }
      Action = "sts:AssumeRole"
      Condition = {
        StringEquals = {
          "aws:SourceAccount" = var.aws_account_id
        }
        ArnLike = {
          "aws:SourceArn" = "arn:aws:s3files:${var.aws_region}:${var.aws_account_id}:file-system/*"
        }
      }
    }]
  })
}

resource "aws_iam_role_policy" "projects_s3files" {
  name = "${var.app_name}-projects-s3files-${var.app_env}"
  role = aws_iam_role.projects_s3files.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "S3BucketPermissions"
        Effect = "Allow"
        Action = [
          "s3:ListBucket",
          "s3:ListBucketVersions"
        ]
        Resource = aws_s3_bucket.projects.arn
        Condition = {
          StringEquals = {
            "aws:ResourceAccount" = var.aws_account_id
          }
        }
      },
      {
        Sid    = "S3ObjectPermissions"
        Effect = "Allow"
        Action = [
          "s3:AbortMultipartUpload",
          "s3:DeleteObject*",
          "s3:GetObject*",
          "s3:List*",
          "s3:PutObject*"
        ]
        Resource = "${aws_s3_bucket.projects.arn}/*"
        Condition = {
          StringEquals = {
            "aws:ResourceAccount" = var.aws_account_id
          }
        }
      },
    ]
  })
}

resource "awscc_s3files_file_system" "projects" {
  bucket   = aws_s3_bucket.projects.arn
  role_arn = aws_iam_role.projects_s3files.arn
}

resource "awscc_s3files_access_point" "projects" {
  file_system_id = awscc_s3files_file_system.projects.file_system_id

  posix_user = {
    gid = 1000
    uid = 1000
  }
}

resource "aws_security_group" "grader_lambda_s3files" {
  name        = "grader-lambda-s3files-${var.app_env}"
  description = "Allow grader Lambda to access the projects S3 Files mount"
  vpc_id      = module.vpc.id
}

resource "aws_security_group" "projects_s3files_mount_targets" {
  name        = "projects-s3files-mount-targets-${var.app_env}"
  description = "Allow S3 Files mount targets to receive NFS traffic from the grader Lambda"
  vpc_id      = module.vpc.id
}

resource "aws_security_group_rule" "projects_s3files_mount_targets_nfs" {
  type                     = "ingress"
  from_port                = 2049
  to_port                  = 2049
  protocol                 = "tcp"
  security_group_id        = aws_security_group.projects_s3files_mount_targets.id
  source_security_group_id = aws_security_group.grader_lambda_s3files.id
}

resource "awscc_s3files_mount_target" "projects" {
  count           = length(module.vpc.public_subnet_ids)
  file_system_id  = awscc_s3files_file_system.projects.file_system_id
  subnet_id       = module.vpc.public_subnet_ids[count.index]
  security_groups = [aws_security_group.projects_s3files_mount_targets.id]
}

// Lambda output goes into artifacts bucket with read-write access?
// Secrets and projects buckets are read-only
data "aws_iam_policy_document" "lambda_s3_access" {
  statement {
    sid    = "S3ReadOnly"
    effect = "Allow"
    actions = [
      "s3:GetObject",
      "s3:GetObjectVersion",
      "s3:ListBucket"
    ]
    resources = [
      aws_s3_bucket.secrets.arn,
      "${aws_s3_bucket.secrets.arn}/*",
      aws_s3_bucket.projects.arn,
      "${aws_s3_bucket.projects.arn}/*"
    ]
  }

  statement {
    sid    = "S3ReadWrite"
    effect = "Allow"
    actions = [
      "s3:GetObject",
      "s3:PutObject",
      "s3:DeleteObject",
      "s3:ListBucket"
    ]
    resources = [
      aws_s3_bucket.artifacts.arn,
      "${aws_s3_bucket.artifacts.arn}/*"
    ]
  }

  statement {
    sid    = "S3FilesClientAccess"
    effect = "Allow"
    actions = [
      "s3files:ClientMount",
      "s3:GetObject",
      "s3:GetObjectVersion",
      "s3:ListBucket",
      "s3:ListBucketVersions"
    ]
    resources = [
      "*"
    ]
  }
}

resource "aws_iam_role_policy" "lambda_s3_policy" {
  name   = "lambda-s3-access-${var.app_env}"
  role   = aws_iam_role.lambda_exec.id
  policy = data.aws_iam_policy_document.lambda_s3_access.json
}

data "archive_file" "dummy" {
  type        = "zip"
  output_path = "${path.module}/lambda_dummy.zip"

  source {
    content  = "Dummy file for inital Lambda deployment. Real code comes from appbuilder-grader CD pipeline."
    filename = "README.txt"
  }
}

resource "aws_s3_object" "lambda_dummy" {
  bucket = aws_s3_bucket.artifacts.bucket
  key    = "lambda_dummy.zip"
  source = data.archive_file.dummy.output_path
}

resource "awscc_lambda_function" "appbuilder_grader" {
  function_name = "${var.app_name}-grader-${var.app_env}"
  role          = aws_iam_role.lambda_exec.arn
  handler       = "bootstrap"
  runtime       = "provided.al2023"
  architectures = ["arm64"]
  timeout       = var.grader_timeout
  memory_size   = var.grader_memory

  code = {
    s3_bucket = aws_s3_bucket.artifacts.bucket
    s3_key    = aws_s3_object.lambda_dummy.key
  }

  vpc_config = {
    subnet_ids         = module.vpc.public_subnet_ids
    security_group_ids = [aws_security_group.grader_lambda_s3files.id]
  }

  file_system_configs = [
    {
      arn              = awscc_s3files_access_point.projects.access_point_arn
      local_mount_path = "/mnt/projects"
    }
  ]

  depends_on = [
    awscc_s3files_mount_target.projects,
    aws_iam_role_policy_attachment.lambda_vpc_access,
  ]

  environment = {
    variables = {
      SECRETS_BUCKET  = aws_s3_bucket.secrets.bucket
      PROJECTS_BUCKET = aws_s3_bucket.projects.bucket
      ARTIFACTS_BUCKET = aws_s3_bucket.artifacts.bucket
    }
  }
}

data "aws_iam_policy_document" "ecs_invoke_lambda" {
  statement {
    effect    = "Allow"
    actions   = ["lambda:InvokeFunction"]
    resources = [awscc_lambda_function.appbuilder_grader.arn]
  }
}

resource "aws_iam_policy" "ecs_invoke_lambda_policy" {
  name   = "ecs-invoke-lambda-${var.app_env}"
  policy = data.aws_iam_policy_document.ecs_invoke_lambda.json
}

resource "aws_iam_role_policy_attachment" "attach_ecs_invoke_lambda" {
  role       = module.ecscluster.ecs_instance_role_id
  policy_arn = aws_iam_policy.ecs_invoke_lambda_policy.arn
}
