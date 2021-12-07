{% if rest_api_gateway %}


  resource "aws_api_gateway_rest_api" "routing_{{routing_id}}" {
    name    = "${var.project_name}-${var.environment}-gateway"
    endpoint_configuration {
      types = ["REGIONAL"]
    }
  }


  resource "aws_api_gateway_deployment" "routing_{{routing_id}}" {
    rest_api_id   = aws_api_gateway_rest_api.routing_{{routing_id}}.id
    depends_on = [
      {% for route in routing_routes %}
        local.gateway_resource_parent_{{route.id}}_id,
      {% endfor %}
      aws_api_gateway_rest_api.routing_{{routing_id}}
    ]

    triggers = {
      # force redeployment on each apply
      redeployment = sha1(timestamp())
    }

    lifecycle {
      create_before_destroy = true
    }
  }

  resource "aws_api_gateway_stage" "routing_{{routing_id}}" {
    rest_api_id   = aws_api_gateway_rest_api.routing_{{routing_id}}.id
    deployment_id = aws_api_gateway_deployment.routing_{{routing_id}}.id
    stage_name        = "default"
  }


  {% for service in routing_services %}
    {% if service.service_type == "container" and service.internal %}

      # Create NLB
      resource "aws_lb" "{{service.name}}" {
          name               = "${var.project_name}-${var.environment}-{{service.name}}"
          internal           = true
          load_balancer_type = "network"
          subnets            = ["{{public_subnet_a_id}}", "{{public_subnet_b_id}}"]
      }

      # Create NLB target group that forwards traffic to alb
      # https://docs.aws.amazon.com/elasticloadbalancing/latest/APIReference/API_CreateTargetGroup.html
      resource "aws_lb_target_group" "{{service.name}}" {
          name         = "${var.project_name}${var.environment}{{service.name}}NL"
          port         = 80
          protocol     = "TCP"
          vpc_id       = "{{main_vpc_id}}"
          target_type  = "alb"
      }

      # Create target group attachment
      # More details: https://docs.aws.amazon.com/elasticloadbalancing/latest/APIReference/API_TargetDescription.html
      # https://docs.aws.amazon.com/elasticloadbalancing/latest/APIReference/API_RegisterTargets.html
      resource "aws_lb_target_group_attachment" "{{service.name}}" {
          target_group_arn = aws_lb_target_group.{{service.name}}.arn
          # target to attach to this target group
          target_id        = "{{service.lb_arn}}"
          #  If the target type is alb, the targeted Application Load Balancer must have at least one listener whose port matches the target group port.
          port             = 80
      }

      resource "aws_lb_listener" "{{service.name}}" {
        load_balancer_arn = aws_lb.{{service.name}}.arn
        port              = "80"
        protocol          = "TCP"

        default_action {
          type             = "forward"
          target_group_arn = aws_lb_target_group.{{service.name}}.arn
        }
      }      

      # create vpc link
      resource "aws_api_gateway_vpc_link" "{{service.name}}" {
        name        = "${var.project_name}-${var.environment}-{{service.name}}"
        target_arns = [aws_lb.{{service.name}}.arn]
      }
    {% elif service.service_type == "serverless" %}

      data "aws_lambda_function" "{{service.name}}" {
        function_name = "{{service.function_name}}"
      }

      # allow GW permissions to this lambda function
      resource "aws_lambda_permission" "{{service.name}}" {
        statement_id  = "AllowExecutionFromAPIGateway"
        action        = "lambda:InvokeFunction"
        function_name = "{{service.function_name}}"
        principal     = "apigateway.amazonaws.com"

        # More: http://docs.aws.amazon.com/apigateway/latest/developerguide/api-gateway-control-access-using-iam-policies-to-invoke-api.html
        source_arn = "${aws_api_gateway_rest_api.routing_{{routing_id}}.execution_arn}/*/*/*"
      }

    {% endif %}
  {% endfor %}

  {% for route in routing_routes %}

    {% if route.route_prefix == "/" %}
      resource "aws_api_gateway_resource" "resource_{{route.id}}_child" {
        rest_api_id = aws_api_gateway_rest_api.routing_{{routing_id}}.id
        parent_id   = aws_api_gateway_rest_api.routing_{{routing_id}}.root_resource_id
        path_part   = "{proxy+}"
      }

      locals {
        gateway_resource_parent_{{route.id}}_id = aws_api_gateway_rest_api.routing_{{routing_id}}.root_resource_id
        gateway_resource_child_{{route.id}}_id = aws_api_gateway_resource.resource_{{route.id}}_child.id

      }
    {% else %}
      resource "aws_api_gateway_resource" "resource_{{route.id}}_parent" {
        rest_api_id = aws_api_gateway_rest_api.routing_{{routing_id}}.id
        parent_id   = aws_api_gateway_rest_api.routing_{{routing_id}}.root_resource_id
        path_part   = "{{route.route_prefix_no_trailing_slash}}"
      }

      resource "aws_api_gateway_resource" "resource_{{route.id}}_child" {
        rest_api_id = aws_api_gateway_rest_api.routing_{{routing_id}}.id
        parent_id   = aws_api_gateway_resource.resource_{{route.id}}_parent.id
        path_part   = "{proxy+}"
      }

      locals {
        gateway_resource_parent_{{route.id}}_id = aws_api_gateway_resource.resource_{{route.id}}_parent.id
        gateway_resource_child_{{route.id}}_id = aws_api_gateway_resource.resource_{{route.id}}_child.id
      }
    {% endif %}


    {% if route.service.service_type == "container" and not route.service.internal %}

      resource "aws_api_gateway_method" "method_{{route.id}}_parent" {
        rest_api_id = aws_api_gateway_rest_api.routing_{{routing_id}}.id
        resource_id = local.gateway_resource_parent_{{route.id}}_id
        http_method   = "ANY"
        authorization = "NONE"
        request_parameters = {
          "method.request.header.Host" = true
        }
      }

      resource "aws_api_gateway_method" "method_{{route.id}}_child" {
        rest_api_id = aws_api_gateway_rest_api.routing_{{routing_id}}.id
        resource_id = local.gateway_resource_child_{{route.id}}_id
        http_method   = "ANY"
        authorization = "NONE"
        request_parameters = {
          "method.request.header.Host" = true
          "method.request.path.proxy"  = true
        }
      }
    

      resource "aws_api_gateway_integration" "integration_{{route.id}}_parent" {
        rest_api_id = aws_api_gateway_rest_api.routing_{{routing_id}}.id
        resource_id = local.gateway_resource_parent_{{route.id}}_id
        http_method = aws_api_gateway_method.method_{{route.id}}_parent.http_method
        type                    = "HTTP_PROXY"
        integration_http_method = "ANY"
        uri                     = "http://{{route.service.lb_url}}"
        connection_type         = "INTERNET"
        timeout_milliseconds    = 29000 # 50-29000
        request_parameters = {
          "integration.request.header.Host" = "method.request.header.Host"
        }
      }

      resource "aws_api_gateway_integration" "integration_{{route.id}}_child" {
        rest_api_id = aws_api_gateway_rest_api.routing_{{routing_id}}.id
        resource_id = local.gateway_resource_child_{{route.id}}_id
        http_method = aws_api_gateway_method.method_{{route.id}}_child.http_method
        type                    = "HTTP_PROXY"
        integration_http_method = "ANY"
        uri                     = "http://{{route.service.lb_url}}/{{route.forward_prefix}}{proxy}"
        connection_type         = "INTERNET"
        timeout_milliseconds    = 29000 # 50-29000
        # cache_key_parameters = ["method.request.path.proxy"]
        request_parameters = {
          "integration.request.path.proxy" = "method.request.path.proxy"
          "integration.request.header.Host" = "method.request.header.Host"
        }
      }


    {% elif route.service.service_type == "container" and route.service.internal %}

      resource "aws_api_gateway_method" "method_{{route.id}}_parent" {
        rest_api_id = aws_api_gateway_rest_api.routing_{{routing_id}}.id
        resource_id = local.gateway_resource_parent_{{route.id}}_id
        http_method   = "ANY"
        authorization = "NONE"
        request_parameters = {
          "method.request.header.Host" = true
        }
      }

      resource "aws_api_gateway_method" "method_{{route.id}}_child" {
        rest_api_id = aws_api_gateway_rest_api.routing_{{routing_id}}.id
        resource_id = local.gateway_resource_child_{{route.id}}_id
        http_method   = "ANY"
        authorization = "NONE"
        request_parameters = {
          "method.request.header.Host" = true
          "method.request.path.proxy"  = true
        }
      }
    

      resource "aws_api_gateway_integration" "integration_{{route.id}}_parent" {
        rest_api_id = aws_api_gateway_rest_api.routing_{{routing_id}}.id
        resource_id = local.gateway_resource_parent_{{route.id}}_id
        http_method = aws_api_gateway_method.method_{{route.id}}_parent.http_method
        type                    = "HTTP_PROXY"
        integration_http_method = "ANY"
        uri                     = join("", ["http://", aws_lb.{{route.service.name}}.dns_name, "/{{route.forward_prefix}}"])
        connection_type         = "VPC_LINK"
        timeout_milliseconds    = 29000 # 50-29000

        connection_id   = aws_api_gateway_vpc_link.{{route.service.name}}.id

        request_parameters = {
          "integration.request.header.Host" = "method.request.header.Host"
        }
      }

      resource "aws_api_gateway_integration" "integration_{{route.id}}_child" {
        rest_api_id = aws_api_gateway_rest_api.routing_{{routing_id}}.id
        resource_id = local.gateway_resource_child_{{route.id}}_id
        http_method = aws_api_gateway_method.method_{{route.id}}_child.http_method
        type                    = "HTTP_PROXY"
        integration_http_method = "ANY"
        uri                     = join("", ["http://", aws_lb.{{route.service.name}}.dns_name, "/{{route.forward_prefix}}{proxy}"])
        connection_type         = "VPC_LINK"
        timeout_milliseconds    = 29000 # 50-29000
        # cache_key_parameters = ["method.request.path.proxy"]

        connection_id   = aws_api_gateway_vpc_link.{{route.service.name}}.id

        request_parameters = {
          "integration.request.path.proxy" = "method.request.path.proxy"
          "integration.request.header.Host" = "method.request.header.Host"
        }
      }

    {% elif route.service.service_type == "serverless" %}

      resource "aws_api_gateway_method" "method_{{route.id}}_parent" {
        rest_api_id = aws_api_gateway_rest_api.routing_{{routing_id}}.id
        resource_id = local.gateway_resource_parent_{{route.id}}_id
        http_method   = "ANY"
        authorization = "NONE"
        request_parameters = {
          "method.request.header.Host" = true
        }
      }

      resource "aws_api_gateway_method" "method_{{route.id}}_child" {
        rest_api_id = aws_api_gateway_rest_api.routing_{{routing_id}}.id
        resource_id = local.gateway_resource_child_{{route.id}}_id
        http_method   = "ANY"
        authorization = "NONE"
        request_parameters = {
          "method.request.header.Host" = true
          "method.request.path.proxy"  = true
        }
      }

      resource "aws_api_gateway_integration" "integration_{{route.id}}_parent" {
        rest_api_id = aws_api_gateway_rest_api.routing_{{routing_id}}.id
        resource_id = local.gateway_resource_parent_{{route.id}}_id
        http_method = aws_api_gateway_method.method_{{route.id}}_parent.http_method
        type                    = "AWS_PROXY"
        integration_http_method = "POST"
        uri                     = data.aws_lambda_function.{{route.service.name}}.invoke_arn

        request_parameters = {
          "integration.request.header.Host" = "method.request.header.Host"
        }
      }

      resource "aws_api_gateway_integration" "integration_{{route.id}}_child" {
        rest_api_id = aws_api_gateway_rest_api.routing_{{routing_id}}.id
        resource_id = local.gateway_resource_child_{{route.id}}_id
        http_method = aws_api_gateway_method.method_{{route.id}}_child.http_method
        type                    = "AWS_PROXY"
        integration_http_method = "POST"
        uri                     = data.aws_lambda_function.{{route.service.name}}.invoke_arn

        request_parameters = {
          "integration.request.path.proxy" = "method.request.path.proxy"
          "integration.request.header.Host" = "method.request.header.Host"
        }
      }

    {% endif %}

  {% endfor %}

  output "lb_url" {
    value = aws_api_gateway_stage.routing_{{routing_id}}.invoke_url
  }

{% endif %}