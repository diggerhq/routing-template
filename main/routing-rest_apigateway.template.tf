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
        aws_api_gateway_resource.resource_{{route.id}}_parent,
      {% endfor %}
      aws_api_gateway_rest_api.routing_{{routing_id}}
    ]

    triggers = {
      # force redeployment on each apply
      redeployment = sha1(timestamp())
    }

  }

  resource "aws_api_gateway_stage" "routing_{{routing_id}}" {
    rest_api_id   = aws_api_gateway_rest_api.routing_{{routing_id}}.id
    deployment_id = aws_api_gateway_deployment.routing_{{routing_id}}.id
    stage_name        = "default"
  }



  {% for route in routing_routes %}

    {% if route.route_prefix == "/" %}
      resource "aws_api_gateway_resource" "resource_{{route.id}}_child" {
        rest_api_id = aws_api_gateway_rest_api.routing_{{routing_id}}.id
        parent_id   = aws_api_gateway_rest_api.routing_{{routing_id}}.root_resource_id
        path_part   = "{proxy+}"
      }

      locals {
        gateway_resource_parent_{{route.id}} = aws_api_gateway_rest_api.routing_{{routing_id}}.root_resource_id
        gateway_resource_child_{{route.id}} = aws_api_gateway_resource.resource_{{route.id}}_child
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
        gateway_resource_parent_{{route.id}} = aws_api_gateway_resource.resource_{{route.id}}_parent
        gateway_resource_child_{{route.id}} = aws_api_gateway_resource.resource_{{route.id}}_child
      }
    {% endif %}


    {% if route.service.service_type == "container" and not route.service.internal %}

      resource "aws_api_gateway_method" "method_{{route.id}}_parent" {
        rest_api_id = aws_api_gateway_rest_api.routing_{{routing_id}}.id
        resource_id = local.gateway_resource_parent_{{route.id}}.id
        http_method   = "ANY"
        authorization = "NONE"
        request_parameters = {
          "method.request.header.Host" = true
        }
      }

      resource "aws_api_gateway_method" "method_{{route.id}}_child" {
        rest_api_id = aws_api_gateway_rest_api.routing_{{routing_id}}.id
        resource_id = local.gateway_resource_child_{{route.id}}.id
        http_method   = "ANY"
        authorization = "NONE"
        request_parameters = {
          "method.request.header.Host" = true
          "method.request.path.proxy"  = true
        }
      }
    

      resource "aws_api_gateway_integration" "integration_{{route.id}}_parent" {
        rest_api_id = aws_api_gateway_rest_api.routing_{{routing_id}}.id
        resource_id = local.gateway_resource_parent_{{route.id}}.id
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
        resource_id = local.gateway_resource_child_{{route.id}}.id
        http_method = aws_api_gateway_method.method_{{route.id}}_child.http_method
        type                    = "HTTP_PROXY"
        integration_http_method = "ANY"
        uri                     = "http://{{route.service.lb_url}}/{proxy}"
        connection_type         = "INTERNET"
        timeout_milliseconds    = 29000 # 50-29000
        # cache_key_parameters = ["method.request.path.proxy"]
        request_parameters = {
          "integration.request.path.proxy" = "method.request.path.proxy"
          "integration.request.header.Host" = "method.request.header.Host"
        }
      }


    {% elif route.service.service_type == "container" and route.service.internal %}

    {% elif route.service.service_type == "serverless" %}
    {% endif %}

  {% endfor %}

  output "lb_url" {
    value = aws_api_gateway_stage.routing_{{routing_id}}.invoke_url
  }

{% endif %}