module "ecs_flask_api" {
  source = "../../../usecases/ecs_flask_db"
  stage  = "dev"
}
