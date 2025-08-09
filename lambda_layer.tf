# Lambda layer for PyJWT and requests dependencies
data "archive_file" "lambda_layer_pyjwt" {
  type        = "zip"
  source_dir  = "${path.module}/lambda_layer/"
  output_path = "${path.module}/lambda_layer.zip"
  
  # Force rebuild by adding a timestamp trigger
  depends_on = [null_resource.layer_trigger]
}

# Trigger to force layer rebuild when packages change
resource "null_resource" "layer_trigger" {
  triggers = {
    # This will change when we modify this comment to force rebuild
    rebuild = "v2-with-requests"
  }
}

resource "aws_lambda_layer_version" "lambda_layer_pyjwt" {
  filename            = data.archive_file.lambda_layer_pyjwt.output_path
  layer_name          = "pyjwt"
  compatible_runtimes = ["python3.12"]
}