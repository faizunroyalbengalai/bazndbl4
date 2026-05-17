terraform {
  backend "azurerm" {}
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.100"
    }
  }
}

provider "azurerm" {
  features {}
}

variable "project_name" {
  type = string
}

variable "azure_region" {
  type    = string
  default = "eastus"
}

variable "docker_image" {
  type = string
}

variable "app_port" {
  type    = number
  default = 3000
}

variable "cpu" {
  type    = number
  default = 0.5
}

variable "memory_gb" {
  type    = number
  default = 1.0
}

variable "registry_server" {
  type    = string
  default = "ghcr.io"
}
variable "registry_username" {
  type    = string
  default = ""
}
variable "registry_password" {
  type      = string
  sensitive = true
  default   = ""
}

variable "db_image" {
  type    = string
  default = ""
}
variable "db_name" {
  type    = string
  default = ""
}
variable "db_username" {
  type    = string
  default = "appuser"
}
variable "db_password" {
  type      = string
  sensitive = true
  default   = ""
}

resource "azurerm_resource_group" "rg" {
  name     = "${var.project_name}-rg"
  location = var.azure_region
  tags = {
    Project   = var.project_name
    ManagedBy = "udap"
  }
}


locals {
  dns_label_base = lower(replace(var.project_name, "_", "-"))
  dns_label      = substr("${local.dns_label_base}-${substr(md5(azurerm_resource_group.rg.id), 0, 6)}", 0, 60)
}

resource "azurerm_container_group" "app" {
  name                = "${var.project_name}-cg"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  os_type             = "Linux"
  ip_address_type     = "Public"
  dns_name_label      = local.dns_label
  restart_policy      = "Always"

  image_registry_credential {
    server   = var.registry_server
    username = var.registry_username
    password = var.registry_password
  }

  container {
    name   = "app"
    image  = var.docker_image
    cpu    = var.cpu
    memory = var.memory_gb

    ports {
      port     = var.app_port
      protocol = "TCP"
    }

    environment_variables = {
      PORT     = tostring(var.app_port)
      NODE_ENV = "production"
      APP_ENV  = "production"
      DB_HOST     = "127.0.0.1"
      DB_PORT     = "5432"
      DB_NAME     = var.db_name != "" ? var.db_name : "${replace(var.project_name, "-", "_")}db"
      DB_USERNAME = var.db_username
      DB_USER     = var.db_username
      DB_TYPE     = "postgres"
    }

    secure_environment_variables = {
      DB_PASSWORD = var.db_password
      DATABASE_URL = "postgresql://${var.db_username}:${var.db_password}@127.0.0.1:5432/${var.db_name != "" ? var.db_name : "${replace(var.project_name, "-", "_")}db"}"
    }
  }

  container {
    name   = "db"
    image  = var.db_image
    cpu    = 0.5
    memory = 1.0

    ports {
      port     = 5432
      protocol = "TCP"
    }

    environment_variables = {
      POSTGRES_DB   = var.db_name != "" ? var.db_name : "${replace(var.project_name, "-", "_")}db"
      POSTGRES_USER = var.db_username
      PGPORT        = "5432"
    }
    secure_environment_variables = {
      POSTGRES_PASSWORD = var.db_password
    }
  }

  tags = {
    Project   = var.project_name
    ManagedBy = "udap"
  }
}

output "public_ip" {
  value = azurerm_container_group.app.ip_address
}

output "fqdn" {
  value = coalesce(azurerm_container_group.app.fqdn, azurerm_container_group.app.ip_address)
}

output "resource_group_name" {
  value = azurerm_resource_group.rg.name
}

output "app_port" {
  value = var.app_port
}

