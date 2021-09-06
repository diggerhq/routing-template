
resource "aws_apigatewayv2_api" "routing_{{routing_id}}" {
  name          = "${var.project_name}-${var.environment}-gateway"
  protocol_type = "HTTP"

  {% if routing_domain %}
  cors_configuration {
    allow_credentials  = true 
    allow_headers      = ["*"]
    allow_methods      = ["*"]
    allow_origins      = "{{routing_domain}}"
    # expose_headers     = ""
    max_age            = 100
  }
  {% endif %}

}


{% if main_vpc_id %}
  resource "aws_security_group" "{{routing_id}}_sg" {
    name        = "${var.project_name}-${var.environment}-vpclink-sg"
    description = "Allow TLS inbound traffic"
    vpc_id      = "{{main_vpc_id}}"
  }

  # Rules for the LB (Targets the task SG)
  resource "aws_security_group_rule" "nsg_task_ingress_rule" {
    description              = "TLS VPCLink ingress"
    type                     = "ingress"
    from_port                = 80
    to_port                  = 80
    protocol                 = "tcp"
    cidr_blocks = ["0.0.0.0"]

    security_group_id = aws_security_group.{{routing_id}}_sg.id
  }

  resource "aws_security_group_rule" "nsg_task_egress_rule" {
    description = "TLS VPCLink egress"
    type        = "egress"
    from_port   = "0"
    to_port     = "0"
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]

    security_group_id = aws_security_group.{{routing_id}}_sg.id
  }
{% endif %}


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
  api_id      = aws_apigatewayv2_api.routing_{{routing_id}}.id
  name        = "$default"
  auto_deploy = true
}


{% for service in routing_services %}
  {% if service.service_type == "container" and not service.internal %}
    resource "aws_apigatewayv2_integration" "{{service.name}}" {
      api_id           = aws_apigatewayv2_api.routing_{{routing_id}}.id
      # credentials_arn  = aws_iam_role.example.arn
      description      = "service {{service.name}} integration"
      integration_type = "HTTP_PROXY"
      integration_uri  = "http://{{service.lb_url}}"

      integration_method = "ANY"
      connection_type    = "INTERNET"

      request_parameters = {
        "overwrite:path" = "$request.path.proxy"
      }    

    }
  {% elif service.service_type == "container" and service.internal %}

    resource "aws_apigatewayv2_vpc_link" "{{service.name}}" {
      name               = "${var.project_name}-{{service.name}}-vpclink"
      security_group_ids = [aws_security_group.{{routing_id}}_sg.id]
      subnet_ids         = ["{{public_subnet_a_id}}", "{{public_subnet_b_id}}"]
    }

    resource "aws_apigatewayv2_integration" "{{service.name}}" {
      api_id           = aws_apigatewayv2_api.routing_{{routing_id}}.id
      # credentials_arn  = aws_iam_role.example.arn
      description      = "Gateway integration for {{service.name}}"
      integration_type = "HTTP_PROXY"
      integration_uri  = "{{service.lb_arn}}"

      integration_method = "ANY"
      connection_type    = "VPC_LINK"
      connection_id      = aws_apigatewayv2_vpc_link.{{service.name}}.id

      request_parameters = {
        "overwrite:path" = "$request.path.proxy"
      }
    }


  {% elif service.service_type == "serverless" %}
    data "aws_lambda_function" "{{service.name}}" {
      function_name = "{{service.function_name}}"
    }

    resource "aws_apigatewayv2_integration" "{{service.name}}" {
      api_id           = aws_apigatewayv2_api.routing_{{routing_id}}.id
      integration_type = "AWS_PROXY"

      connection_type           = "INTERNET"
      description               = "Lambda {{service.name}}"
      integration_method        = "POST"
      integration_uri           = data.aws_lambda_function.{{service.name}}.invoke_arn
      passthrough_behavior      = "WHEN_NO_MATCH"

      request_parameters = {
        "overwrite:path" = "$request.path.proxy"
      }
    }

    # gateway permission
    resource "aws_lambda_permission" "lambda_permission_{{service.name}}" {
      statement_id  = "${var.project_name}${var.environment}{{service.name}}GWAPIInvoke"
      action        = "lambda:InvokeFunction"
      function_name = data.aws_lambda_function.{{service.name}}.function_name
      principal     = "apigateway.amazonaws.com"

      # The /*/*/* part allows invocation from any stage, method and resource path
      # within API Gateway
      source_arn = "${aws_apigatewayv2_api.routing_{{routing_id}}.execution_arn}/*/*/*"
    }
  {% endif %}
{% endfor %}


{% for route in routing_routes %}
  resource "aws_apigatewayv2_route" "route_{{route.id}}" {
    api_id    = aws_apigatewayv2_api.routing_{{routing_id}}.id
    route_key = "ANY {{route.route_prefix}}{proxy+}"
    target = "integrations/${aws_apigatewayv2_integration.{{route.service_name}}.id}"

    lifecycle {
      ignore_changes = [
        authorization_scopes,
        authorization_type,
        authorizer_id,
      ]
    }
  }
{% endfor %}

output "lb_url" {
  value = aws_apigatewayv2_api.routing_{{routing_id}}.api_endpoint
}