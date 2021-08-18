
resource "aws_apigatewayv2_api" "routing" {
  name          = "${var.project_name}-${var.environment}-gateway"
  protocol_type = "HTTP"

  {% if routing_domain %}
  cors_configuration {
    allow_credentials  = true 
    allow_headers      = "*"
    allow_methods      = "*"
    allow_origins      = "{{routing_domain}}"
    # expose_headers     = ""
    max_age            = 100
  }
  {% endif %}

}

{% if routing_domain and routing_certificate %}
resource "aws_apigatewayv2_domain_name" "domain_{{routing_id}}" {
  domain_name = "{{routing_domain}}"

  domain_name_configuration {
    certificate_arn = "{{routing_certificate}}"
    endpoint_type   = "REGIONAL"
    security_policy = "TLS_1_2"
  }
}
{% endif %}

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
  resource "aws_apigatewayv2_route" "route_{{routing_id}}" {
    api_id    = aws_apigatewayv2_api.example.id
    route_key = "ANY {{route.path}}{proxy+}"
    target = "integrations/${aws_apigatewayv2_integration.{{service.name}}.id}"
  }
{% endfor}
