
resource "aws_apigatewayv2_api" "routing" {
  name          = "${var.project_name}-${var.environment}-gateway"
  protocol_type = "HTTP"
}

resource "aws_apigatewayv2_stage" "routing" {
  api_id      = aws_apigatewayv2_api.routing.id
  name        = "$default"
  auto_deploy = true
}


{% for service in routing_services %}
  {% if service.service_type == "container" not and service.internal %}
    resource "aws_apigatewayv2_integration" "{{service.name}}" {
      api_id           = aws_apigatewayv2_api.example.id
      # credentials_arn  = aws_iam_role.example.arn
      description      = "service {{service.name}} integration"
      integration_type = "HTTP_PROXY"
      integration_uri  = "http://{{service.lb_url}}"

      integration_method = "ANY"
      connection_type    = "INTERNET"
    }
  {% elif service.service_type == "container" not service.internal %}
    # TODOO: this should be VPC link
    resource "aws_apigatewayv2_integration" "{{service.name}}" {
      api_id           = aws_apigatewayv2_api.example.id
      # credentials_arn  = aws_iam_role.example.arn
      description      = "service {{service.name}} integration"
      integration_type = "HTTP_PROXY"
      integration_uri  = "http://{{service.lb_url}}"

      integration_method = "ANY"
      connection_type    = "INTERNET"
    }
  {% elif service.service_type == "lambda" %}

  {% endif %}
{% endfor %}


{% for route in routing_routes %}
  resource "aws_apigatewayv2_route" "route_{{route.id}}" {
    api_id    = aws_apigatewayv2_api.example.id
    route_key = "ANY {{route.path}}{proxy+}"
    target = "integrations/${aws_apigatewayv2_integration.{{service.name}}.id}"
  }
{% endfor}
