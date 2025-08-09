# Lambda layer for PyJWT dependency
data "archive_file" "lambda_layer_pyjwt" {
  type        = "zip"
  source_dir  = "${path.module}/lambda_layer/"
  output_path = "${path.module}/lambda_layer.zip"
}

resource "aws_lambda_layer_version" "lambda_layer_pyjwt" {
  filename            = data.archive_file.lambda_layer_pyjwt.output_path
  layer_name          = "pyjwt"
  compatible_runtimes = ["python3.12"]
}