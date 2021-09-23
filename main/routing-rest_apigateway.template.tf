{% if rest_api_gateway %}
  resource "aws_api_gateway_rest_api" "routing_{{routing_id}}" {
    name          = "${var.project_name}-${var.environment}-gateway"
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



  {% for route in routing_routes %}
    resource "aws_api_gateway_resource" "resource_{{route.id}}_parent" {
      rest_api_id = aws_api_gateway_rest_api.routing_{{routing_id}}.id
      parent_id   = aws_api_gateway_rest_api.routing_{{routing_id}}.root_resource_id
      path_part   = "{{route.route_prefix}}"
    }

    resource "aws_api_gateway_resource" "resource_{{route.id}}_child" {
      rest_api_id = aws_api_gateway_rest_api.routing_{{routing_id}}.id
      parent_id   = aws_api_gateway_resource.resource_{{route.id}}_parent.id
      path_part   = "{proxy+}"
    }


    {% if route.service.service_type == "container" and not route.service.internal %}

      resource "aws_api_gateway_method" "method_{{route.id}}_parent" {
        rest_api_id = aws_api_gateway_rest_api.routing_{{routing_id}}.id
        resource_id = aws_api_gateway_resource.resource_{{route.id}}_parent.id
        http_method   = "ANY"
        authorization = "NONE"
      }

      resource "aws_api_gateway_method" "method_{{route.id}}_child" {
        rest_api_id = aws_api_gateway_rest_api.routing_{{routing_id}}.id
        resource_id = aws_api_gateway_resource.resource_{{route.id}}_child.id
        http_method   = "ANY"
        authorization = "NONE"
      }

      resource "aws_api_gateway_integration" "integration_{{route.id}}_parent" {
        rest_api_id = aws_api_gateway_rest_api.routing_{{routing_id}}.id
        resource_id = aws_api_gateway_resource.resource_{{route.id}}_parent.id
        http_method = aws_api_gateway_method.method_{{route.id}}_parent.http_method
        type                    = "HTTP_PROXY"
        integration_http_method = "ANY"
        uri                     = "http://{{route.service.lb_url}}"
        connection_type         = "INTERNET"
        timeout_milliseconds    = 29000 # 50-29000
      }

      resource "aws_api_gateway_integration" "integration_{{route.id}}_child" {
        rest_api_id = aws_api_gateway_rest_api.routing_{{routing_id}}.id
        resource_id = aws_api_gateway_resource.resource_{{route.id}}_child.id
        http_method = aws_api_gateway_method.method_{{route.id}}_child.http_method
        type                    = "HTTP_PROXY"
        integration_http_method = "ANY"
        uri                     = "http://{{route.service.lb_url}}/{proxy}"
        connection_type         = "INTERNET"
        timeout_milliseconds    = 29000 # 50-29000
        # cache_key_parameters = ["method.request.path.proxy"]
        # request_parameters = {
        #   "integration.request.path.proxy" = "method.request.path.proxy"
        # }
      }


    {% elif route.service.service_type == "container" and route.service.internal %}

    {% elif route.service.service_type == "serverless" %}
    {% endif %}

  {% endfor %}

  output "lb_url" {
    value = aws_api_gateway_stage.routing_{{routing_id}}.invoke_url
  }

{% endif %}