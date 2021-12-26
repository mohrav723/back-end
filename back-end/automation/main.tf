# provider, region, access and secret key
provider "aws" {
    region = "us-west-1"
    access_key = "AKIAYODDKO36FSP3ZFM3"
    secret_key = "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"
}

# role and inline policy for lambda function to access dynamodb table

resource "aws_iam_role_policy" "terraform_lambda_policy" {
  name = "terraform_lambda_policy"
  role = aws_iam_role.terraform_lambda_role.id

  # Terraform's "jsonencode" function converts a
  # Terraform expression result to valid JSON syntax.
  policy = "${file("iam-policy-lambda/lambda-policy.json")}"
}

resource "aws_iam_role" "terraform_lambda_role" {
  name = "terraform_lambda_role"

  assume_role_policy = "${file("iam-policy-lambda/lambda-assume-policy.json")}"
}

locals {
  lambda_zip_location = "src/lambda_function.zip"
}

# creating the lambda function
# code in main.py, but lambda launching from terraform uses packaged code under src -> lambda_function.zip

data "archive_file" "terraform_lambda" {
  type        = "zip"
  source_file = "main.py"
  output_path = "${local.lambda_zip_location}"
}

resource "aws_lambda_function" "terraform_lambda" {
  filename      = "${local.lambda_zip_location}"
  function_name = "terraform_lambda"
  role          = aws_iam_role.terraform_lambda_role.arn
  handler       = "main.lambda_handler"

  # source_code_hash = "${base64sha256(file("lambda_function_payload.zip"))}"

  runtime = "python3.9"
}

# api gateway
resource "aws_api_gateway_rest_api" "terraform_api" {
    name          = "terraform_api"
    description   = "API by terraform"
}

# api resource
resource "aws_api_gateway_resource" "api_resource" {
    path_part     = "method"
    parent_id     = aws_api_gateway_rest_api.terraform_api.root_resource_id
    rest_api_id   = aws_api_gateway_rest_api.terraform_api.id
}

# options method
resource "aws_api_gateway_method" "options_method" {
    rest_api_id   = aws_api_gateway_rest_api.terraform_api.id
    resource_id   = aws_api_gateway_resource.api_resource.id
    http_method   = "OPTIONS"
    authorization = "NONE"
}

# options method response
resource "aws_api_gateway_method_response" "options_200" {
    rest_api_id   = aws_api_gateway_rest_api.terraform_api.id
    resource_id   = aws_api_gateway_resource.api_resource.id
    http_method   = aws_api_gateway_method.options_method.http_method
    status_code   = "200"
    response_models = {
        "application/json" = "Empty"
    }
    response_parameters = {
        "method.response.header.Access-Control-Allow-Headers" = true,
        "method.response.header.Access-Control-Allow-Methods" = true,
        "method.response.header.Access-Control-Allow-Origin" = true
    }
    depends_on = [aws_api_gateway_method.options_method]
}


# options integration
resource "aws_api_gateway_integration" "options_integration" {
    rest_api_id   = aws_api_gateway_rest_api.terraform_api.id
    resource_id   = aws_api_gateway_resource.api_resource.id
    http_method   = aws_api_gateway_method.options_method.http_method
    type          = "MOCK"
    depends_on = [aws_api_gateway_method.options_method]
}

# options integration response
resource "aws_api_gateway_integration_response" "options_integration_response" {
    rest_api_id   = aws_api_gateway_rest_api.terraform_api.id
    resource_id   = aws_api_gateway_resource.api_resource.id
    http_method   = aws_api_gateway_method.options_method.http_method
    status_code   = aws_api_gateway_method_response.options_200.status_code
    response_parameters = {
        "method.response.header.Access-Control-Allow-Headers" = "'Content-Type,X-Amz-Date,Authorization,X-Api-Key,X-Amz-Security-Token'",
        "method.response.header.Access-Control-Allow-Methods" = "'GET,OPTIONS,POST,PUT'",
        "method.response.header.Access-Control-Allow-Origin" = "'*'"
    }
    depends_on = [aws_api_gateway_method_response.options_200]
}

# post method
resource "aws_api_gateway_method" "post_method" {
    rest_api_id   = aws_api_gateway_rest_api.terraform_api.id
    resource_id   = aws_api_gateway_resource.api_resource.id
    http_method   = "POST"
    authorization = "NONE"
}

# post method response
resource "aws_api_gateway_method_response" "post_method_response_200" {
    rest_api_id   = aws_api_gateway_rest_api.terraform_api.id
    resource_id   = aws_api_gateway_resource.api_resource.id
    http_method   = aws_api_gateway_method.post_method.http_method
    status_code   = "200"
    response_parameters = {
        "method.response.header.Access-Control-Allow-Headers" = true,
        "method.response.header.Access-Control-Allow-Methods" = true,
        "method.response.header.Access-Control-Allow-Origin" = true
    }
    depends_on = [aws_api_gateway_method.post_method]
}

# post integration
resource "aws_api_gateway_integration" "integration" {
    rest_api_id   = aws_api_gateway_rest_api.terraform_api.id
    resource_id   = aws_api_gateway_resource.api_resource.id
    http_method   = aws_api_gateway_method.post_method.http_method
    integration_http_method = "POST"
    type          = "AWS"
    uri           = aws_lambda_function.terraform_lambda.invoke_arn
    depends_on    = [aws_api_gateway_method.post_method, aws_lambda_function.terraform_lambda]
}

# post integration response
resource "aws_api_gateway_integration_response" "integration_response" {
  rest_api_id = aws_api_gateway_rest_api.terraform_api.id
  resource_id = aws_api_gateway_resource.api_resource.id
  http_method = aws_api_gateway_method.post_method.http_method
  status_code = aws_api_gateway_method_response.post_method_response_200.status_code
  
    response_parameters  = {
        "method.response.header.Access-Control-Allow-Headers" = "'Content-Type,X-Amz-Date,Authorization,X-Api-Key,X-Amz-Security-Token'",
        "method.response.header.Access-Control-Allow-Methods" = "'GET,OPTIONS,POST,PUT'", 
        "method.response.header.Access-Control-Allow-Origin" = "'*'"
      } 
     depends_on = [aws_api_gateway_method_response.post_method_response_200]
}


# deploy api
resource "aws_api_gateway_deployment" "deployment" {
    rest_api_id   = aws_api_gateway_rest_api.terraform_api.id
    stage_name    = "Dev"
    depends_on    = [aws_api_gateway_integration.integration]
}

resource "aws_lambda_permission" "apigw_lambda" {
    statement_id  = "AllowExecutionFromAPIGateway"
    action        = "lambda:InvokeFunction"
    function_name = aws_lambda_function.terraform_lambda.arn
    principal     = "apigateway.amazonaws.com"
}

# create dynamodb table to store view counter data

resource "aws_dynamodb_table_item" "records" {
  table_name = aws_dynamodb_table.records.name
  hash_key   = aws_dynamodb_table.records.hash_key
 
  item = <<ITEM
{
  "record_id": {"S": "0"},
  "record_count": {"N": "450"}
}
ITEM
}
resource "aws_dynamodb_table" "records" {
  name           = "visitor_table"
  billing_mode   = "PAY_PER_REQUEST"
  hash_key       = "record_id"

  attribute {
    name = "record_id"
    type = "S"
  }
}
