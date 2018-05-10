// Create VPC
module "vpc" {
  source    = "github.com/silinternational/terraform-modules//aws/vpc-public-only?ref=develop"
  app_name  = "${var.app_name}"
  app_env   = "${var.app_env}"
  aws_zones = "${var.aws_zones}"
}

// Create ecs cluster
module "ecscluster" {
  source   = "github.com/silinternational/terraform-modules//aws/ecs/cluster?ref=develop"
  app_name = "${var.app_name}"
  app_env  = "${var.app_env}"
}

// Create user for CI/CD to perform ECS actions
resource "aws_iam_user" "codeship" {
  name = "codeship-${var.app_name}-${var.app_env}"
}

resource "aws_iam_access_key" "codeship" {
  user = "${aws_iam_user.codeship.name}"
}

resource "aws_iam_user_policy" "ecs" {
  name = "ECS-ECR"
  user = "${aws_iam_user.codeship.name}"

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
  vpc_id      = "${module.vpc.id}"
}

resource "aws_security_group_rule" "mysql" {
  count             = "${var.db_access_enabled == "true" ? 1 : 0}"
  type              = "ingress"
  from_port         = 3306
  to_port           = 3306
  protocol          = "tcp"
  security_group_id = "${aws_security_group.db_access_limited_ips.id}"
  cidr_blocks       = ["${var.db_access_ips}"]
}

// Create database and root password
resource "random_id" "db_root_pass" {
  byte_length = 16
}

// Create DB
module "rds" {
  source                  = "github.com/silinternational/terraform-modules//aws/rds/mariadb?ref=develop"
  app_name                = "${var.app_name}"
  app_env                 = "${var.app_env}"
  db_name                 = "${var.db_name}"
  db_root_user            = "${var.db_root_user}"
  db_root_pass            = "${random_id.db_root_pass.hex}"
  subnet_group_name       = "${module.vpc.db_subnet_group_name}"
  availability_zone       = "${var.aws_zones[0]}"
  security_groups         = ["${module.vpc.vpc_default_sg_id}"]
  allocated_storage       = "${var.db_storage}"
  backup_retention_period = "${var.db_backup_retention_period}"
  multi_az                = "${var.db_multi_az}"
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
  vpc_id      = "${module.vpc.id}"
}

resource "aws_security_group_rule" "ssh" {
  count             = "${var.ssh_enabled == "true" ? 1 : 0}"
  type              = "ingress"
  from_port         = 22
  to_port           = 22
  protocol          = "tcp"
  security_group_id = "${aws_security_group.ec2_ssh_limited_ips.id}"
  cidr_blocks       = ["${var.ssh_ips}"]
}

// Create auto-scaling group
module "asg" {
  source                     = "github.com/silinternational/terraform-modules//aws/asg?ref=develop"
  app_name                   = "${var.app_name}"
  app_env                    = "${var.app_env}"
  aws_instance               = "${var.aws_instance}"
  private_subnet_ids         = ["${module.vpc.private_subnet_ids}"]
  default_sg_id              = "${module.vpc.vpc_default_sg_id}"
  additional_security_groups = ["${aws_security_group.ec2_ssh_limited_ips.id}"]
  ecs_instance_profile_id    = "${module.ecscluster.ecs_instance_profile_id}"
  ecs_cluster_name           = "${module.ecscluster.ecs_cluster_name}"
  ami_id                     = "${data.aws_ami.ecs_ami.id}"
}

// Get ssl cert for use with listener
data "aws_acm_certificate" "appbuilder" {
  domain = "${var.cert_domain_name}"
}

// Create security group that allows 443 from specific IPs
resource "aws_security_group" "alb_https_limited_ips" {
  name        = "https-limited-ips"
  description = "Allow HTTPS traffic from limited IPs"
  vpc_id      = "${module.vpc.id}"
}

resource "aws_security_group_rule" "https" {
  type              = "ingress"
  from_port         = 443
  to_port           = 443
  protocol          = "tcp"
  security_group_id = "${aws_security_group.alb_https_limited_ips.id}"
  cidr_blocks       = ["${var.https_ips}"]
}

// Create application load balancer for public access
module "alb" {
  source          = "github.com/silinternational/terraform-modules//aws/alb?ref=develop"
  app_name        = "${var.app_name}"
  app_env         = "${var.app_env}"
  internal        = "false"
  vpc_id          = "${module.vpc.id}"
  security_groups = ["${module.vpc.vpc_default_sg_id}", "${aws_security_group.alb_https_limited_ips.id}"]
  subnets         = ["${module.vpc.public_subnet_ids}"]
  certificate_arn = "${data.aws_acm_certificate.appbuilder.arn}"
}

// Create S3 bucket for storing artifacts
data "template_file" "artifacts_bucket_policy" {
  template = "${file("${path.module}/s3-artifact-bucket-policy.json")}"

  vars {
    bucket_name = "${var.app_env}-${var.org_prefix}-${var.app_name}-artifacts"
  }
}

// Artifacts stuff - S3, IAM
resource "aws_s3_bucket" "artifacts" {
  bucket        = "${var.org_prefix}-${var.app_env}-${var.app_name}-artifacts"
  acl           = "public-read"
  policy        = "${data.template_file.artifacts_bucket_policy.rendered}"
  force_destroy = true

  website {
    index_document = "index.html"
    error_document = "error.html"
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

// CodeCommit repository and IAM policy
resource "aws_codecommit_repository" "ciscripts" {
  repository_name = "ci-scripts-${var.app_env}"
  description     = "CodeCommit Repository for Job DSL configuration"
}

resource "aws_iam_policy" "ciscripts" {
  name        = "codecommit-ci-scripts-${var.app_env}"
  description = "CodeCommit Repository for Job DSL configuration"

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
                "${aws_codecommit_repository.ciscripts.arn}"
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
                "arn:aws:codecommit:${var.aws_region}:${var.aws_account_id}:projects-${var.app_env}-*"
            ]
        }
    ]
}
EOF
}

// Create appbuilder IAM user, policy attachments, SSH key, and put private key in S3
resource "aws_iam_user" "appbuilder" {
  name = "appbuilder-${var.app_env}"
}

resource "aws_iam_access_key" "appbuilder" {
  user = "${aws_iam_user.appbuilder.name}"
}

resource "aws_iam_user_policy_attachment" "appbuilder-artifacts" {
  user       = "${aws_iam_user.appbuilder.name}"
  policy_arn = "${aws_iam_policy.artifacts.arn}"
}

resource "aws_iam_user_policy_attachment" "appbuilder-projects" {
  user       = "${aws_iam_user.appbuilder.name}"
  policy_arn = "${aws_iam_policy.codecommit_projects.arn}"
}

resource "aws_iam_user_policy_attachment" "appbuilder-secrets" {
  user       = "${aws_iam_user.appbuilder.name}"
  policy_arn = "${aws_iam_policy.secrets.arn}"
}

resource "tls_private_key" "appbuilder" {
  algorithm = "RSA"
}

resource "aws_iam_user_ssh_key" "appbuilder" {
  username   = "${aws_iam_user.appbuilder.name}"
  encoding   = "SSH"
  public_key = "${tls_private_key.appbuilder.public_key_pem}"
}

resource "aws_s3_bucket_object" "appbuilder_build_ssh_private_key" {
  bucket  = "${aws_s3_bucket.secrets}"
  key     = "jenkins/build/appbuilder_ssh/id_rsa"
  content = "${tls_private_key.appbuilder.private_key_pem}"
}

resource "aws_s3_bucket_object" "appbuilder_publish_ssh_private_key" {
  bucket  = "${aws_s3_bucket.secrets}"
  key     = "jenkins/publish/appbuilder_ssh/id_rsa"
  content = "${tls_private_key.appbuilder.private_key_pem}"
}

// Create buildengine IAM user, policy attachments, SSH key, and put private key in S3
resource "aws_iam_user" "buildengine" {
  name = "buildengine-${var.app_env}"
}

resource "aws_iam_access_key" "buildengine" {
  user = "${aws_iam_user.buildengine.name}"
}

resource "aws_iam_user_policy_attachment" "buildengine-artifacts" {
  user       = "${aws_iam_user.buildengine.name}"
  policy_arn = "${aws_iam_policy.artifacts.arn}"
}

resource "aws_iam_user_policy_attachment" "buildengine-ciscripts" {
  user       = "${aws_iam_user.buildengine.name}"
  policy_arn = "${aws_iam_policy.ciscripts.arn}"
}

resource "aws_iam_user_policy_attachment" "buildengine-secrets" {
  user       = "${aws_iam_user.buildengine.name}"
  policy_arn = "${aws_iam_policy.secrets.arn}"
}

resource "tls_private_key" "buildengine" {
  algorithm = "RSA"
}

resource "aws_iam_user_ssh_key" "buildengine" {
  username   = "${aws_iam_user.buildengine.name}"
  encoding   = "SSH"
  public_key = "${tls_private_key.buildengine.public_key_pem}"
}

resource "aws_s3_bucket_object" "buildengine_ssh_private_key" {
  bucket  = "${aws_s3_bucket.secrets}"
  key     = "buildengine_api/ssh/id_rsa"
  content = "${tls_private_key.buildengine.private_key_pem}"
}

// Create ECS service for buildengine
resource "random_id" "api_access_token" {
  byte_length = 16
}

resource "random_id" "front_cookie_key" {
  byte_length = 16
}

data "template_file" "task_def_buildengine" {
  template = "${file("${path.module}/task-def-buildengine.json")}"

  vars {
    api_cpu                         = "${var.api_cpu}"
    api_memory                      = "${var.api_memory}"
    cron_cpu                        = "${var.cron_cpu}"
    cron_memory                     = "${var.cron_memory}"
    docker_image                    = "${var.buildengine_docker_image}"
    docker_tag                      = "${var.buildengine_docker_tag}"
    ADMIN_EMAIL                     = "${var.admin_email}"
    API_ACCESS_TOKEN                = "${random_id.api_access_token.hex}"
    APPBUILDER_GIT_SSH_USER         = "${aws_iam_user_ssh_key.appbuilder.ssh_public_key_id}"
    APP_ENV                         = "${var.app_env}"
    AWS_ACCESS_KEY_ID               = "${aws_iam_access_key.buildengine.id}"
    AWS_SECRET_ACCESS_KEY           = "${aws_iam_access_key.buildengine.secret}"
    BUILD_ENGINE_ARTIFACTS_BUCKET   = "${aws_s3_bucket.artifacts.bucket}"
    BUILD_ENGINE_GIT_SSH_USER       = "${aws_iam_user_ssh_key.buildengine.ssh_public_key_id}"
    BUILD_ENGINE_GIT_USER_EMAIL     = "${var.buildengine_git_user_email}"
    BUILD_ENGINE_GIT_USER_NAME      = "${var.buildengine_git_user_name}"
    BUILD_ENGINE_JENKINS_MASTER_URL = "http://${var.jenkins_subdomain}.${var.domain}:8080"
    BUILD_ENGINE_REPO_BRANCH        = "${var.buildengine_repo_branch}"
    BUILD_ENGINE_REPO_URL           = "${aws_codecommit_repository.ciscripts.clone_url_ssh}"
    EXPAND_S3_FILES                 = "${aws_s3_bucket.secrets.bucket}/buildengine_api/ssh/id_rsa|/root/.ssh/id_rsa[600,]"
    EXPAND_S3_KEY                   = "${aws_iam_access_key.buildengine.id}"
    EXPAND_S3_SECRET                = "${aws_iam_access_key.buildengine.secret}"
    FRONT_COOKIE_KEY                = "${random_id.front_cookie_key.hex}"
    LOGENTRIES_KEY                  = "${var.logentries_key}"
    MAILER_PASSWORD                 = "${var.mailer_password}"
    MAILER_USEFILES                 = "${var.mailer_usefiles}"
    MAILER_USERNAME                 = "${var.mailer_username}"
    MYSQL_DATABASE                  = "${var.db_name}"
    MYSQL_HOST                      = "${module.rds.address}"
    MYSQL_PASSWORD                  = "${random_id.db_root_pass.hex}"
    MYSQL_USER                      = "${var.db_root_user}"
    PUBLISH_JENKINS_MASTER_URL      = "http://${var.jenkins_subdomain}.${var.domain}:8080"
  }
}

// Uses default target group to route all https/443 traffic to buildengine
module "ecsservice_buildengine" {
  source             = "github.com/silinternational/terraform-modules//aws/ecs/service-only?ref=develop"
  cluster_id         = "${module.ecscluster.ecs_cluster_id}"
  service_name       = "buildengine"
  service_env        = "${var.app_env}"
  container_def_json = "${data.template_file.task_def_buildengine.rendered}"
  desired_count      = 1
  tg_arn             = "${module.alb.default_tg_arn}"
  lb_container_name  = "web"
  lb_container_port  = 80
  ecsServiceRole_arn = "${module.ecscluster.ecsServiceRole_arn}"
}

// Create ECS service for appbuilder
data "template_file" "task_def_appbuilder" {
  template = "${file("${path.module}/task-def-appbuilder.json")}"

  vars {
    appbuilder_agent_cpu            = "${var.appbuilder_agent_cpu}"
    appbuilder_agent_docker_image   = "${var.appbuilder_agent_docker_image}"
    appbuilder_agent_docker_tag     = "${var.appbuilder_agent_docker_tag}"
    appbuilder_agent_memory         = "${var.appbuilder_agent_memory}"
    appbuilder_jenkins_cpu          = "${var.appbuilder_jenkins_cpu}"
    appbuilder_jenkins_docker_image = "${var.appbuilder_jenkins_docker_image}"
    appbuilder_jenkins_docker_tag   = "${var.appbuilder_jenkins_docker_tag}"
    appbuilder_jenkins_memory       = "${var.appbuilder_jenkins_memory}"
    APPBUILDER_JENKINS_URL          = "http://${var.jenkins_subdomain}.${var.domain}:8080"
    BUILD_ENGINE_GIT_SSH_USER       = "${aws_iam_user_ssh_key.buildengine.ssh_public_key_id}"
    BUILD_ENGINE_REPO_BRANCH        = "${var.buildengine_repo_branch}"
    BUILD_ENGINE_REPO_URL           = "${aws_codecommit_repository.ciscripts.clone_url_ssh}"
    EXPAND_S3_FOLDERS               = "${aws_s3_bucket.secrets.bucket}/|/usr/share/jenkins/secrets"
    EXPAND_S3_KEY                   = "${aws_iam_access_key.buildengine.id}"
    EXPAND_S3_SECRET                = "${aws_iam_access_key.buildengine.secret}"
  }
}

resource "aws_alb_target_group" "appbuilder" {
  name     = "appbuilder-${var.app_env}"
  port     = "8080"
  protocol = "HTTP"
  vpc_id   = "${module.vpc.id}"

  health_check {
    matcher = "200"
  }
}

resource "aws_alb_listener" "appbuilder" {
  load_balancer_arn = "${module.alb.arn}"
  port              = "8080"
  protocol          = "HTTP"

  default_action {
    target_group_arn = "${aws_alb_target_group.appbuilder.arn}"
    type             = "forward"
  }
}

module "ecsservice_appbuilder" {
  source             = "github.com/silinternational/terraform-modules//aws/ecs/service-only?ref=develop"
  cluster_id         = "${module.ecscluster.ecs_cluster_id}"
  service_name       = "appbuilder"
  service_env        = "${var.app_env}"
  container_def_json = "${data.template_file.task_def_appbuilder.rendered}"
  desired_count      = 1
  tg_arn             = "${aws_alb_target_group.appbuilder.arn}"
  lb_container_name  = "appbuilder"
  lb_container_port  = 8080
  ecsServiceRole_arn = "${module.ecscluster.ecsServiceRole_arn}"
}
