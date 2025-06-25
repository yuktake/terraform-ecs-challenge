resource "aws_ecs_cluster" "flask_api" {
  name = "${var.stage}-flask-api-tf"
}

resource "aws_ecs_cluster_capacity_providers" "flask_api" {
  capacity_providers = [
    "FARGATE",
  ]
  cluster_name = aws_ecs_cluster.flask_api.name
}

# すでに作成したSSMパラメータストアについてのデータソース
data "aws_ssm_parameter" "flask_api_correct_answer" {
  name = "/flask-api-tf/${var.stage}/correct_answer"
}

# DBユーザー名をSSMパラメータストアから取得
data "aws_ssm_parameter" "db_user" {
  name = "/flask-api-tf/${var.stage}/db_user"
}

# DBパスワードをSSMパラメータストアから取得
data "aws_ssm_parameter" "db_password" {
  name = "/flask-api-tf/${var.stage}/db_password"
}

# DB名をSSMパラメータストアから取得
data "aws_ssm_parameter" "db_name" {
  name = "/flask-api-tf/${var.stage}/db_name"
}

data "aws_ssm_parameter" "db_host" {
  name = "/flask-api-tf/${var.stage}/db_host"
}

# 既存のrdsセキュリティグループを取得
data "aws_security_group" "rds_sg" {
  name   = "${var.stage}-flask_api_rds_tf"
}

# 既存のEC2セキュリティグループを取得
data "aws_security_group" "ec2_sg" {
    name   = "${var.stage}-flask_api_ec2_tf"
}

# 信頼関係ポリシー
data "aws_iam_policy_document" "ecs_task_execution_assume_role" {
  statement {
    effect = "Allow"
    actions = [
      "sts:AssumeRole"
    ]
    principals {
      identifiers = [
        "ecs-tasks.amazonaws.com"
      ]
      type = "Service"
    }
  }
}

# ECRやCloudWatch Logsのアクションを許可するAWSマネージドポリシー
data "aws_iam_policy" "managed_ecs_task_execution" {
  name = "AmazonECSTaskExecutionRolePolicy"
}

# タスク実行ロールにアタッチするインラインポリシー
# 起動時にSSMパラメータストアから環境変数を取得するのでその許可を記述
data "aws_iam_policy_document" "ecs_task_execution" {
  statement {
    effect = "Allow"
    actions = [
      "ssm:GetParameters",
      "ssm:GetParameter",
      "ssm:GetParametersByPath",
    ]
    # 参照できるパラメータストアを限定
    resources = [
      data.aws_ssm_parameter.flask_api_correct_answer.arn,
      data.aws_ssm_parameter.db_user.arn,
      data.aws_ssm_parameter.db_password.arn,
      data.aws_ssm_parameter.db_name.arn,
      # ここが怪しくて、depends_onでの対応が必要かも
      data.aws_ssm_parameter.db_host.arn
    ]
  }
}

# 復号化されたパラメータを取得するためのポリシー
data "aws_iam_policy_document" "ecs_task_execution_decryption" {
  statement {
    effect = "Allow"
    actions = [
      "kms:Decrypt"
    ]
    resources = [
      # マネージドキーの場合は*でよい
      "*"
    ]
  }
}

# s3アクセス用のポリシー
data "aws_iam_policy_document" "ecs_s3_access" {
  statement {
    effect    = "Allow"
    actions   = ["s3:GetObject", "s3:ListBucket"]
    resources = ["arn:aws:s3:::*"]
  }
}

data "aws_route_tables" "private" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.this.id]
  }
}

# IAMロールを記述
resource "aws_iam_role" "ecs_task_execution_role" {
  name               = "${var.stage}-flask-api-execution-role-tf"
  assume_role_policy = data.aws_iam_policy_document.ecs_task_execution_assume_role.json
}

# IAMロールにAWSマネージドポリシーをアタッチ
resource "aws_iam_role_policy_attachments_exclusive" "ecs_task_execution_managed_policy" {
  policy_arns = [data.aws_iam_policy.managed_ecs_task_execution.arn]
  role_name   = aws_iam_role.ecs_task_execution_role.name
}

# IAMロールにインラインポリシーをアタッチ
resource "aws_iam_role_policy" "ecs_task_execution_inline_policy" {
  name   = "${var.stage}-flask-api-ecs-task-execution-policy"
  policy = data.aws_iam_policy_document.ecs_task_execution.json
  role   = aws_iam_role.ecs_task_execution_role.name
}

# IAMロールに復号化ポリシーをアタッチ
resource "aws_iam_role_policy" "ecs_task_execution_decryption_policy" {
  name   = "${var.stage}-flask-api-ecs-task-execution-decryption-policy"
  policy = data.aws_iam_policy_document.ecs_task_execution_decryption.json
  role   = aws_iam_role.ecs_task_execution_role.name
}

# IAMロールにS3アクセスポリシーをアタッチ
resource "aws_iam_role_policy" "ecs_task_s3_access" {
  name   = "${var.stage}-flask-api-ecs-task-s3-access-policy"
  policy = data.aws_iam_policy_document.ecs_s3_access.json
  role   = aws_iam_role.ecs_task_execution_role.name
}

# 信頼関係ポリシー
data "aws_iam_policy_document" "ecs_task_assume_role" {
  statement {
    effect = "Allow"
    actions = [
      "sts:AssumeRole"
    ]
    principals {
      identifiers = [
        "ecs-tasks.amazonaws.com"
      ]
      type = "Service"
    }
  }
}

# タスクロールにアタッチするインラインポリシー
data "aws_iam_policy_document" "ecs_task" {
  # ECS Execの実行に必要なアクションを許可
  statement {
    effect = "Allow"
    actions = [
      "ssmmessages:CreateControlChannel",
      "ssmmessages:CreateDataChannel",
      "ssmmessages:OpenControlChannel",
      "ssmmessages:OpenDataChannel"
    ]
    resources = ["*"]
  }
}

# タスクロールを記述
resource "aws_iam_role" "ecs_task" {
  name               = "${var.stage}-flask-api-ecs-task-role-tf"
  assume_role_policy = data.aws_iam_policy_document.ecs_task_assume_role.json
}

# タスクロールにインラインポリシーをアタッチ
resource "aws_iam_role_policy" "ecs_task_inline_policy" {
  name   = "${var.stage}-flask-api-ecs-task-policy"
  policy = data.aws_iam_policy_document.ecs_task.json
  role   = aws_iam_role.ecs_task.name
}

# 何回か参照するVPC名をlocalsで定義しておく
locals {
  vpc_name = "${var.stage}-vpc-tf"
}

# データソースによるVPCの情報の照会
# Name というタグの値で指定
data "aws_vpc" "this" {
  filter {
    name   = "tag:Name"
    values = [local.vpc_name]
  }
}
# データソースによるサブネットの情報の照会
# Name というタグの値で指定
data "aws_subnets" "public" {
  filter {
    name = "tag:Name"
    values = [
      "${local.vpc_name}-public-ap-northeast-1a",
      "${local.vpc_name}-public-ap-northeast-1c",
      "${local.vpc_name}-public-ap-northeast-1d"
    ]
  }
}

data "aws_subnets" "private" {
  filter {
    name = "tag:Name"
    values = [
      "${local.vpc_name}-private-ap-northeast-1a",
      "${local.vpc_name}-private-ap-northeast-1c",
      "${local.vpc_name}-private-ap-northeast-1d"
    ]
  }
}

# ALB 用のセキュリティグループ
resource "aws_security_group" "alb" {
  name   = "${var.stage}-flask_api_alb_tf"
  vpc_id = data.aws_vpc.this.id
}

# ECS Fargate インスタンス用のセキュリティグループ
resource "aws_security_group" "ecs_sg" {
  name   = "${var.stage}-flask_api_ecs_instance_tf"
  vpc_id = data.aws_vpc.this.id
}

# ALB 用のセキュリティグループのインバウンドルール
# 任意のIPアドレスからの80番ポートへの接続を許可
resource "aws_vpc_security_group_ingress_rule" "lb_from_http" {
  ip_protocol       = "tcp"
  security_group_id = aws_security_group.alb.id
  from_port         = 80
  to_port           = 80
  cidr_ipv4         = "0.0.0.0/0"
}

# ALB 用のセキュリティグループのアウトバウンドルール
# ECS Fargate インスタンスの5000番ポートへの接続を許可
resource "aws_vpc_security_group_egress_rule" "lb_to_ecs_instance" {
  ip_protocol       = "tcp"
  security_group_id = aws_security_group.alb.id
  from_port         = 5000
  to_port           = 5000
  # ECS Fargate インスタンス用のセキュリティグループがアタッチされた ENI への通信を許可
  referenced_security_group_id = aws_security_group.ecs_sg.id
}

# ECS Fargate インスタンス用のセキュリティグループのインバウンドルール
# ALB からの5000番ポートへの接続を許可
resource "aws_vpc_security_group_ingress_rule" "ecs_instance_from_lb" {
  ip_protocol       = "tcp"
  security_group_id = aws_security_group.ecs_sg.id
  from_port         = 5000
  to_port           = 5000
  # ALB 用のセキュリティグループがアタッチされた ENI からの通信を許可
  referenced_security_group_id = aws_security_group.alb.id
}

# ECS Fargate インスタンス用のセキュリティグループのアウトバウンドルール
# 任意のIPアドレスの443番ポートへの接続を許可
# AWS API のエンドポイント(ECR, SSMなど)と通信できるようにするため
resource "aws_vpc_security_group_egress_rule" "ecs_instance_to_https" {
  ip_protocol       = "tcp"
  security_group_id = aws_security_group.ecs_sg.id
  from_port         = 443
  to_port           = 443
  cidr_ipv4         = "0.0.0.0/0"
}

# ECS FargateからRDSへのアウトバウンドルール
resource "aws_vpc_security_group_egress_rule" "ecs_instance_to_rds" {
  ip_protocol       = "tcp"
  security_group_id = aws_security_group.ecs_sg.id
  from_port         = 3306
  to_port           = 3306
  # RDS用のセキュリティグループがアタッチされた ENI への通信を許可
  referenced_security_group_id = data.aws_security_group.rds_sg.id
}

# ALB 本体
resource "aws_lb" "flask_api" {
  name               = "${var.stage}-flask-api-alb-tf"
  internal           = false
  load_balancer_type = "application"
  # ALB用のセキュリティグループを指定
  security_groups = [aws_security_group.alb.id]
  # パブリックサブネットに配置
  subnets = data.aws_subnets.public.ids
}

# ALBのターゲットグループ
# 5000番ポートで通信を受け付ける
resource "aws_lb_target_group" "flask_api" {
  name        = "flask-api-tf"
  port        = 5000
  protocol    = "HTTP"
  target_type = "ip"
  vpc_id      = data.aws_vpc.this.id
  health_check {
    path     = "/health"
    protocol = "HTTP"
    matcher  = "200"
    interval = 10
  }
}

# ALBのリスナー
# 80番ポートで受け付けたリクエストをターゲットグループに転送
resource "aws_lb_listener" "flask_api" {
  load_balancer_arn = aws_lb.flask_api.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.flask_api.arn
  }
}

# リージョンの問い合わせ
data "aws_region" "current" {}

# ECRリポジトリの問い合わせ
data "aws_ecr_repository" "flask_api" {
  name = "${var.stage}-flask-api-tf"
}

# ECSタスクのロググループ
resource "aws_cloudwatch_log_group" "flask_api" {
  name              = "/ecs/${var.stage}-flask-api-tf"
  retention_in_days = 90
}

# コンテナ定義を locals で定義しておく。
# このようにすることで、aws_ecs_task_definition の container_definitions 以外からも参照できる
locals {
  container_definitions = {
    # flask-api コンテナのコンテナ定義
    flask_api = {
      name = "flask-api"
      # 環境変数 CORRECT_ANSWER はSSMパラメータストアから取得
      secrets = [
        {
          name      = "CORRECT_ANSWER"
          valueFrom = data.aws_ssm_parameter.flask_api_correct_answer.arn
        },
        {
          name      = "DB_USER"
          valueFrom = data.aws_ssm_parameter.db_user.arn
        },
        {
          name      = "DB_PASSWORD"
          valueFrom = data.aws_ssm_parameter.db_password.arn
        },
        {
          name      = "DB_NAME"
          valueFrom = data.aws_ssm_parameter.db_name.arn
        },
        {
          name      = "HOST"
          valueFrom = data.aws_ssm_parameter.db_host.arn
        },
      ]
      essential = true
      # ECR レポジトリのデータソースを参照
      image = "${data.aws_ecr_repository.flask_api.repository_url}:latest"
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          awslogs-group         = aws_cloudwatch_log_group.flask_api.name
          awslogs-region        = data.aws_region.current.name
          awslogs-stream-prefix = "flask_api"
        }
      }
      portMappings = [
        {
          containerPort = 5000
          hostPort      = 5000
          protocol      = "tcp"
        },
      ]
    },
  }
}

resource "aws_ecs_task_definition" "flask_api" {
  # jsonencode を使うと、HCLの記述(JSONの記述法が混在していてもよい)をJSONに変換してくれる
  # values() を使うとマップの値だけをリストとして取得できる
  container_definitions = jsonencode(
    values(local.container_definitions)
  )
  cpu                = "256"
  execution_role_arn = aws_iam_role.ecs_task_execution_role.arn
  family             = "${var.stage}-flask-api-tf"
  memory             = "512"
  network_mode       = "awsvpc"
  requires_compatibilities = [
    "FARGATE",
  ]
  task_role_arn = aws_iam_role.ecs_task.arn
  # タスク定義の過去バージョンを削除しない
  skip_destroy = true
}

resource "aws_ecs_service" "flask_api" {
  cluster                           = aws_ecs_cluster.flask_api.arn
  # デプロイした後に手動で変更する
  # 自動スケーリングさせたい場合は別途サービスの別項目で設定が必要
  desired_count                     = 0
  enable_execute_command            = true
  health_check_grace_period_seconds = 60
  launch_type                       = "FARGATE"
  name                              = "flask-api-tf"
  task_definition                   = aws_ecs_task_definition.flask_api.arn

  # デプロイに失敗しても再起動を繰り返さないようにサーキットブレーカーを入れておく
  deployment_circuit_breaker {
    enable   = true
    rollback = false
  }

  load_balancer {
    # container_definitions を locals のマップにしておくことでコンテナ名を参照できる
    container_name   = local.container_definitions.flask_api.name
    container_port   = 5000
    target_group_arn = aws_lb_target_group.flask_api.arn
  }

  network_configuration {
    security_groups = [
      aws_security_group.ecs_sg.id
    ]
    # このケースではプライベートサブネットにECS Fargateインスタンスを配置する
    subnets          = data.aws_subnets.private.ids
    assign_public_ip = false
  }

  lifecycle {
    ignore_changes = [
      # desired_count は変動するので、差分を無視する
      desired_count
    ]
  }
}

resource "aws_vpc_endpoint" "ssm" {
  vpc_id            = data.aws_vpc.this.id
  service_name      = "com.amazonaws.${data.aws_region.current.name}.ssm"
  vpc_endpoint_type = "Interface"
  subnet_ids        = data.aws_subnets.private.ids
  security_group_ids = [aws_security_group.vpc_endpoint_sg.id]
  # プライベートDNSを有効にする
  private_dns_enabled = true
}

resource "aws_vpc_endpoint" "ssmmessages" {
  vpc_id            = data.aws_vpc.this.id
  service_name      = "com.amazonaws.${data.aws_region.current.name}.ssmmessages"
  vpc_endpoint_type = "Interface"
  subnet_ids        = data.aws_subnets.private.ids
  security_group_ids = [aws_security_group.vpc_endpoint_sg.id]
  private_dns_enabled = true
}

# ECR用エンドポイント（API用と DKR 用）
resource "aws_vpc_endpoint" "ecr_api" {
  vpc_id            = data.aws_vpc.this.id
  service_name      = "com.amazonaws.${data.aws_region.current.name}.ecr.api"
  vpc_endpoint_type = "Interface"
  subnet_ids        = data.aws_subnets.private.ids
  security_group_ids = [aws_security_group.vpc_endpoint_sg.id]
  private_dns_enabled = true
}

resource "aws_vpc_endpoint" "ecr_dkr" {
  vpc_id            = data.aws_vpc.this.id
  service_name      = "com.amazonaws.${data.aws_region.current.name}.ecr.dkr"
  vpc_endpoint_type = "Interface"
  subnet_ids        = data.aws_subnets.private.ids
  security_group_ids = [aws_security_group.vpc_endpoint_sg.id]
  private_dns_enabled = true
}

resource "aws_vpc_endpoint" "ec2messages" {
  vpc_id            = data.aws_vpc.this.id
  service_name      = "com.amazonaws.${data.aws_region.current.name}.ec2messages"
  vpc_endpoint_type = "Interface"
  subnet_ids        = data.aws_subnets.private.ids
  security_group_ids = [aws_security_group.vpc_endpoint_sg.id]
  private_dns_enabled = true
}

# kms 用エンドポイント
resource "aws_vpc_endpoint" "kms" {
  vpc_id            = data.aws_vpc.this.id
  service_name      = "com.amazonaws.${data.aws_region.current.name}.kms"
  vpc_endpoint_type = "Interface"
  subnet_ids        = data.aws_subnets.private.ids
  security_group_ids = [aws_security_group.vpc_endpoint_sg.id]
  private_dns_enabled = true
}

resource "aws_vpc_endpoint" "logs" {
  vpc_id            = data.aws_vpc.this.id
  service_name      = "com.amazonaws.${data.aws_region.current.name}.logs"
  vpc_endpoint_type = "Interface"
  subnet_ids        = data.aws_subnets.private.ids
  security_group_ids = [aws_security_group.vpc_endpoint_sg.id]
  private_dns_enabled = true
}

resource "aws_vpc_endpoint" "s3" {
  vpc_id       = data.aws_vpc.this.id
  service_name = "com.amazonaws.${data.aws_region.current.name}.s3"
  vpc_endpoint_type = "Gateway"
  route_table_ids = data.aws_route_tables.private.ids
}

# VPCエンドポイント用セキュリティグループ
resource "aws_security_group" "vpc_endpoint_sg" {
  name  = "${var.stage}-flask_api_vpc_endpoint_sg_tf"
  vpc_id = data.aws_vpc.this.id
}

# ECSからVPCエンドポイントへの接続を許可
resource "aws_vpc_security_group_ingress_rule" "https_from_ecs" {
  security_group_id = aws_security_group.vpc_endpoint_sg.id
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
  referenced_security_group_id = aws_security_group.ecs_sg.id
}

# EC2からVPCエンドポイントへのインバウンドルール
resource "aws_vpc_security_group_ingress_rule" "https_from_ec2" {
  security_group_id = aws_security_group.vpc_endpoint_sg.id
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
  referenced_security_group_id = data.aws_security_group.ec2_sg.id
}

# EC2からVPCエンドポイントへのアウトバウンドルール
resource "aws_vpc_security_group_egress_rule" "ec2_to_vpc_endpoint" {
  security_group_id = data.aws_security_group.ec2_sg.id
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
  referenced_security_group_id = aws_security_group.vpc_endpoint_sg.id
}

# EC2からRDSへのアウトバウンドルール
resource "aws_vpc_security_group_egress_rule" "ec2_to_rds" {
  security_group_id = data.aws_security_group.ec2_sg.id
  ip_protocol       = "tcp"
  from_port         = 3306
  to_port           = 3306
  referenced_security_group_id = data.aws_security_group.rds_sg.id
}

# VPCエンドポイントのアウトバウンドルール
resource "aws_vpc_security_group_egress_rule" "vpc_endpoint_to_ecs" {
  security_group_id = aws_security_group.vpc_endpoint_sg.id
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
  cidr_ipv4         = "0.0.0.0/0"
}

# RDSのセキュリティグループのインバウンドルール
# ECS Fargate からの接続を許可
resource "aws_vpc_security_group_ingress_rule" "rds_from_ecs" {
  ip_protocol       = "tcp"
  security_group_id = data.aws_security_group.rds_sg.id
  from_port         = 3306
  to_port           = 3306
  referenced_security_group_id = aws_security_group.ecs_sg.id
}