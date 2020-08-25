// Create VPC
module "vpc" {
  source    = "github.com/silinternational/terraform-modules//aws/vpc-public-only?ref=3.0.1"
  app_name  = var.app_name
  app_env   = var.app_env
  aws_zones = var.aws_zones
}

// Create ecs cluster
module "ecscluster" {
  source   = "github.com/silinternational/terraform-modules//aws/ecs/cluster?ref=3.0.1"
  app_name = var.app_name
  app_env  = var.app_env
}

// Create user for CI/CD to perform ECS actions
resource "aws_iam_user" "codeship" {
  name = "codeship-${var.app_name}-${var.app_env}"
}

resource "aws_iam_access_key" "codeship" {
  user = aws_iam_user.codeship.name
}

resource "aws_iam_user_policy" "ecs" {
  name = "ECS-ECR"
  user = aws_iam_user.codeship.name

  policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "ecs:DeregisterTaskDefinition",
        "ecs:DescribeServices",
        "ecs:DescribeTaskDefinition",
        "ecs:DescribeTasks",
        "ecs:ListTasks",
        "ecs:ListTaskDefinitions",
        "ecs:RegisterTaskDefinition",
        "ecs:StartTask",
        "ecs:StopTask",
        "ecs:UpdateService",
        "iam:PassRole"
      ],
      "Resource": "*"
    },
    {
        "Effect": "Allow",
        "Action": [
            "ecr:GetAuthorizationToken"
        ],
        "Resource": [
            "*"
        ]
    }
  ]
}
EOF

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
  cidr_blocks       = var.db_access_ips
}

resource "aws_security_group_rule" "postgres" {
  count             = var.db_access_enabled == "true" ? 1 : 0
  type              = "ingress"
  from_port         = 5432
  to_port           = 5432
  protocol          = "tcp"
  security_group_id = aws_security_group.db_access_limited_ips.id
  cidr_blocks       = var.db_access_ips
}

// Create database and root password
resource "random_id" "buildengine_db_root_pass" {
  byte_length = 16
}

// Create DB
module "rds" {
  source                  = "github.com/silinternational/terraform-modules//aws/rds/mariadb?ref=3.0.1"
  app_name                = var.app_name
  app_env                 = var.app_env
  db_name                 = var.buildengine_db_name
  db_root_user            = var.buildengine_db_root_user
  db_root_pass            = random_id.buildengine_db_root_pass.hex
  subnet_group_name       = module.vpc.db_subnet_group_name
  availability_zone       = var.aws_zones[0]
  security_groups         = [module.vpc.vpc_default_sg_id, aws_security_group.db_access_limited_ips.id]
  allocated_storage       = var.db_storage
  backup_retention_period = var.db_backup_retention_period
  multi_az                = var.db_multi_az
  publicly_accessible     = "true"
}

// Determine most recent ECS optimized AMI
data "aws_ami" "ecs_ami" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["amzn-ami-*-amazon-ecs-optimized"]
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
  cidr_blocks       = var.ssh_ips
}

// Create EC2 host for ECS cluster
data "template_file" "user_data" {
  template = file("${path.module}/user-data.sh")

  vars = {
    ecs_cluster_name = module.ecscluster.ecs_cluster_name
  }
}

resource "aws_instance" "ecshost" {
  ami                    = data.aws_ami.ecs_ami.id
  instance_type          = var.aws_instance["instance_type"]
  key_name               = var.ec2_ssh_key_name
  vpc_security_group_ids = [module.vpc.vpc_default_sg_id, aws_security_group.ec2_ssh_limited_ips.id]
  iam_instance_profile   = module.ecscluster.ecs_instance_profile_id
  user_data              = data.template_file.user_data.rendered
  subnet_id              = module.vpc.public_subnet_ids[0]

  root_block_device {
    volume_size = var.aws_instance["volume_size"]
  }

  tags = {
    Name     = "${var.app_name}-${var.app_env}"
    app_name = var.app_name
    app_env  = var.app_env
  }
}

resource "aws_eip" "public" {
  vpc      = true
  instance = aws_instance.ecshost.id

  tags = {
    app_name = var.app_name
    app_env  = var.app_env
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
  cidr_blocks       = concat(var.https_ips, ["${aws_eip.public.public_ip}/32"])
}

resource "aws_security_group_rule" "limited_dwkit" {
  type              = "ingress"
  from_port         = 7081
  to_port           = 7081
  protocol          = "tcp"
  security_group_id = aws_security_group.alb_https_limited_ips.id
  cidr_blocks       = concat(var.https_ips, ["${aws_eip.public.public_ip}/32"])
}

// Create application load balancer for public access
module "alb" {
  source          = "github.com/silinternational/terraform-modules//aws/alb?ref=3.0.1"
  app_name        = var.app_name
  app_env         = var.app_env
  internal        = "false"
  vpc_id          = module.vpc.id
  security_groups = [module.vpc.vpc_default_sg_id, aws_security_group.alb_https_limited_ips.id]
  subnets         = module.vpc.public_subnet_ids
  certificate_arn = data.aws_acm_certificate.appbuilder.arn
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
  name                 = replace("tg-buildengine-${var.app_env}", "/(.{0,32})(.*)/", "$1")
  port                 = "80"
  protocol             = "HTTP"
  vpc_id               = module.vpc.id
  deregistration_delay = "30"

  stickiness {
    type = "lb_cookie"
  }
}

resource "aws_alb_listener" "dwkit" {
  default_action {
    target_group_arn = module.alb.default_tg_arn
    type             = "forward"
  }

  load_balancer_arn = module.alb.arn
  port              = 7081
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-2016-08"
  certificate_arn   = data.aws_acm_certificate.appbuilder.arn
}

// Create S3 bucket for storing artifacts
data "template_file" "artifacts_bucket_policy" {
  template = file("${path.module}/s3-artifact-bucket-policy.json")

  vars = {
    bucket_name = "${var.org_prefix}-${var.app_env}-${var.app_name}-files"
  }
}

// Artifacts stuff - S3, IAM
// Use "files" insteads of "artifacts" for user facing bucket name
resource "aws_s3_bucket" "artifacts" {
  bucket        = "${var.org_prefix}-${var.app_env}-${var.app_name}-files"
  acl           = "public-read"
  policy        = data.template_file.artifacts_bucket_policy.rendered
  force_destroy = true

  website {
    index_document = "index.html"
    error_document = "error.html"
  }

  tags = {
    app_name = var.app_name
    app_env  = var.app_env
  }
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
  acl           = "private"
  force_destroy = true

  versioning {
    enabled = true
  }

  lifecycle_rule {
    id      = "delete-old-versions"
    enabled = true

    noncurrent_version_expiration {
      days = 30
    }
  }

  tags = {
    app_name = var.app_name
    app_env  = var.app_env
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
  acl           = "private"
  force_destroy = true

  versioning {
    enabled = true
  }

  lifecycle_rule {
    id      = "delete-really-old-versions"
    enabled = true

    noncurrent_version_expiration {
      days = 365
    }
  }

  tags = {
    app_name = var.app_name
    app_env  = var.app_env
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

resource "aws_iam_policy" "codecommit_projects" {
  name        = "codecommit-projects-${var.app_env}"
  description = "CodeCommit Repository for project data"

  policy = <<EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "codecommit:GetBranch",
                "codecommit:GitPull",
                "codecommit:GitPush",
                "codecommit:ListBranches"
            ],
            "Resource": [
                "arn:aws:codecommit:${var.aws_region}:${var.aws_account_id}:*"
            ]
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
                "codebuild:StartBuild"
            ],
            "Resource": "*"
        },
        {
            "Sid": "VisualEditor1",
            "Effect": "Allow",
            "Action": [
                "codecommit:GetRepository",
                "codecommit:CreateRepository",
                "codecommit:DeleteRepository",
                "codecommit:GetBranch",
                "codecommit:ListBranches"
            ],
            "Resource": "arn:aws:codecommit:${var.aws_region}:${var.aws_account_id}:*"
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

resource "aws_iam_role_policy_attachment" "build-codecommit-projects" {
  policy_arn = aws_iam_policy.codecommit_projects.arn
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

resource "aws_iam_user_policy_attachment" "appbuilder-projects" {
  user       = aws_iam_user.appbuilder.name
  policy_arn = aws_iam_policy.codecommit_projects.arn
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

data "template_file" "task_def_buildengine" {
  template = file("${path.module}/task-def-buildengine.json")

  vars = {
    api_cpu                              = var.buildengine_api_cpu
    api_memory                           = var.buildengine_api_memory
    cron_cpu                             = var.buildengine_cron_cpu
    cron_memory                          = var.buildengine_cron_memory
    buildengine_docker_image             = var.buildengine_docker_image
    buildengine_docker_tag               = var.buildengine_docker_tag
    ADMIN_EMAIL                          = var.admin_email
    API_ACCESS_TOKEN                     = random_id.api_access_token.hex
    API_BASE_URL                         = var.buildengine_api_base_url
    APP_ENV                              = var.app_env
    AWS_ACCESS_KEY_ID                    = aws_iam_access_key.buildengine.id
    AWS_SECRET_ACCESS_KEY                = aws_iam_access_key.buildengine.secret
    AWS_USER_ID                          = var.aws_account_id
    BUILD_ENGINE_ARTIFACTS_BUCKET        = aws_s3_bucket.artifacts.bucket
    BUILD_ENGINE_ARTIFACTS_BUCKET_REGION = var.aws_region
    BUILD_ENGINE_PROJECTS_BUCKET         = aws_s3_bucket.projects.bucket
    BUILD_ENGINE_SECRETS_BUCKET          = aws_s3_bucket.secrets.bucket
    CODE_BUILD_IMAGE_REPO                = "${var.aws_account_id}.dkr.ecr.${var.aws_region}.amazonaws.com/${var.buildagent_code_build_image_repo}"
    CODE_BUILD_IMAGE_TAG                 = var.buildagent_code_build_image_tag
    FRONT_COOKIE_KEY                     = random_id.front_cookie_key.hex
    LOGENTRIES_KEY                       = var.logentries_key
    MAILER_PASSWORD                      = var.mailer_password
    MAILER_USEFILES                      = var.mailer_usefiles
    MAILER_USERNAME                      = var.mailer_username
    MYSQL_DATABASE                       = var.buildengine_db_name
    MYSQL_HOST                           = module.rds.address
    MYSQL_PASSWORD                       = random_id.buildengine_db_root_pass.hex
    MYSQL_USER                           = var.buildengine_db_root_user
  }
}

// Create ECR Repo for Build Agent
resource "aws_ecr_repository" "agent" {
  name = var.buildagent_code_build_image_repo
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

// Uses default target group to route all https/443 traffic to buildengine
module "ecsservice_buildengine" {
  source             = "github.com/silinternational/terraform-modules//aws/ecs/service-only?ref=3.0.1"
  cluster_id         = module.ecscluster.ecs_cluster_id
  service_name       = "buildengine"
  service_env        = var.app_env
  container_def_json = data.template_file.task_def_buildengine.rendered
  desired_count      = 1
  tg_arn             = aws_alb_target_group.buildengine.arn
  lb_container_name  = "web"
  lb_container_port  = 80
  ecsServiceRole_arn = module.ecscluster.ecsServiceRole_arn
}

// Create DNS CNAME record on Cloudflare for Agent API

resource "cloudflare_record" "buildengine" {
  domain  = var.cloudflare_domain
  name    = "${var.app_sub_domain}-buildengine"
  type    = "CNAME"
  value   = module.alb.dns_name
  proxied = false
}

