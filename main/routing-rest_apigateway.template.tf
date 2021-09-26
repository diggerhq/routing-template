{% if rest_api_gateway %}

  data "template_file" "swagger"{
    template = file("./rest_gateway_swagger.yml")
  }

  resource "aws_api_gateway_rest_api" "routing_{{routing_id}}" {
    name    = "${var.project_name}-${var.environment}-gateway"
    body    = data.template_file.swagger.rendered
    endpoint_configuration {
      types = ["REGIONAL"]
    }
  }


  resource "aws_api_gateway_deployment" "routing_{{routing_id}}" {
    rest_api_id   = aws_api_gateway_rest_api.routing_{{routing_id}}.id
  }

  resource "aws_api_gateway_stage" "routing_{{routing_id}}" {
    rest_api_id   = aws_api_gateway_rest_api.routing_{{routing_id}}.id
    deployment_id = aws_api_gateway_deployment.routing_{{routing_id}}.id
    stage_name        = "default"
  }

  output "lb_url" {
    value = aws_api_gateway_stage.routing_{{routing_id}}.invoke_url
  }

{% endif %}