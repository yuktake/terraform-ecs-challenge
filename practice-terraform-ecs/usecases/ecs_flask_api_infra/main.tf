resource "aws_ecr_repository" "flask_api" {
  name = "${var.stage}-flask-api-tf"
}
resource "aws_ssm_parameter" "flask_api_correct_answer" {
  name  = "/flask-api-tf/${var.stage}/correct_answer"
  type  = "SecureString"
  value = "uninitialized"
  # 格納された値が変更されても無視する
  lifecycle {
    ignore_changes = [
      value
    ]
  }
}

# DBユーザ名をSSMパラメータストアに格納
resource "aws_ssm_parameter" "db_user" {
  name  = "/flask-api-tf/${var.stage}/db_user"
  type  = "SecureString"
  value = "uninitialized"
  lifecycle {
    ignore_changes = [
      value
    ]
  }
}

# DB名をSSMパラメータストアに格納
resource "aws_ssm_parameter" "db_name" {
  name  = "/flask-api-tf/${var.stage}/db_name"
  type  = "SecureString"
  value = "uninitialized"
  lifecycle {
    ignore_changes = [
      value
    ]
  }
}

# DBのパスワードをSSMパラメータストアに格納
resource "aws_ssm_parameter" "db_password" {
  name  = "/flask-api-tf/${var.stage}/db_password"
  type  = "SecureString"
  value = "uninitialized"
  lifecycle {
    ignore_changes = [
      value
    ]
  }
}