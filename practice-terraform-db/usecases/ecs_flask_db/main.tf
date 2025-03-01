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

# リージョンの問い合わせ
data "aws_region" "current" {}

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

data "aws_subnets" "intra" {
  filter {
    name = "tag:Name"
    values = [
      "${local.vpc_name}-intra-ap-northeast-1a",
      "${local.vpc_name}-intra-ap-northeast-1c",
      "${local.vpc_name}-intra-ap-northeast-1d"
    ]
  }
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

# ------------RDS Aurora MySQL------------

resource "aws_ssm_parameter" "db_host" {
  name  = "/flask-api-tf/${var.stage}/db_host"
  type  = "SecureString"
  value = aws_rds_cluster.aurora.endpoint
  lifecycle {
    ignore_changes = [
      value
    ]
  }
}

# RDS用のセキュリティグループ
resource "aws_security_group" "rds_sg" {
  name   = "${var.stage}-flask_api_rds_tf"
  vpc_id = data.aws_vpc.this.id
}

# RDSのアウトバウンドルール
resource "aws_vpc_security_group_egress_rule" "rds_to_all" {
  ip_protocol       = "-1"
  security_group_id = aws_security_group.rds_sg.id
  cidr_ipv4         = "0.0.0.0/0"
}

# RDS用のサブネットグループ
resource "aws_db_subnet_group" "aurora" {
  name       = "${var.stage}-aurora-subnet-group"
  subnet_ids = data.aws_subnets.intra.ids
}

# Auroraクラスター
resource "aws_rds_cluster" "aurora" {
  cluster_identifier      = "${var.stage}-aurora-cluster"
  engine                 = "aurora-mysql"
  engine_version         = "8.0.mysql_aurora.3.07.1"
  database_name          = data.aws_ssm_parameter.db_name.value
  master_username        = data.aws_ssm_parameter.db_user.value
  master_password        = data.aws_ssm_parameter.db_password.value
  db_subnet_group_name   = aws_db_subnet_group.aurora.name
  vpc_security_group_ids = [aws_security_group.rds_sg.id]
  skip_final_snapshot    = true
}

# Auroraクラスターのインスタンス
resource "aws_rds_cluster_instance" "aurora_instance" {
  cluster_identifier   = aws_rds_cluster.aurora.id
  instance_class       = "db.t3.medium"
  engine              = aws_rds_cluster.aurora.engine
  engine_version      = aws_rds_cluster.aurora.engine_version
  publicly_accessible = false
  # countを指定しない場合、サブネットグループに指定したAZの中から任意のAZに配置される
  # 本来であれば、複数のインスタンスをAZに分散させるために countとavailability_zoneを使う
  # count = 2
  # availability_zone = element(data.aws_region.current.availability_zones, count.index)
}

# ------------EC2------------

# EC2のセキュリティグループ
resource "aws_security_group" "ec2_sg" {
  name   = "${var.stage}-flask_api_ec2_tf"
  vpc_id = data.aws_vpc.this.id
}

# EC2からRDSへの接続を許可
resource "aws_vpc_security_group_ingress_rule" "rds_from_ec2" {
  ip_protocol       = "tcp"
  security_group_id = aws_security_group.rds_sg.id
  from_port         = 3306
  to_port           = 3306
  referenced_security_group_id = aws_security_group.ec2_sg.id  # EC2のセキュリティグループ
}

# EC2のロール
resource "aws_iam_role" "ssm_role" {
  name = "EC2-SSM-Role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
      Action = "sts:AssumeRole"
    }]
  })
}

# EC2のロールにSSMのポリシーをアタッチ
resource "aws_iam_role_policy_attachment" "ssm_policy" {
  role       = aws_iam_role.ssm_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

# プライベートサブネットにRDSに接続するためのEC2インスタンスを配置
resource "aws_instance" "ec2" {
  ami           = "ami-08ce76bae392de7dc"
  instance_type = "t3.micro"
  subnet_id     = data.aws_subnets.private.ids[0]
  security_groups = [
    aws_security_group.ec2_sg.id
  ]
  iam_instance_profile = aws_iam_instance_profile.ssm_profile.name
  tags = {
    Name = "${var.stage}-flask-api-ec2-tf"
  }
}

# EC2のインスタンスプロファイル
# インスタンスプロファイルとは、EC2インスタンスにアタッチするIAMロールのこと
resource "aws_iam_instance_profile" "ssm_profile" {
  name = "ssm_profile"
  role = aws_iam_role.ssm_role.name
}