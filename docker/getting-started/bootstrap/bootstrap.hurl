# Wait for Dashboard to be ready with retries
GET http://tyk-dashboard:3000/hello
[Options]
retry: 10
retry-interval: 3000
HTTP 200
[Asserts]
status == 200

# Create default Organization
POST http://tyk-dashboard:3000/admin/organisations/
admin-auth: {{admin_secret}}
Content-Type: application/json
{
    "owner_name": "Tyk Demo",
    "cname_enabled": true,
    "event_options": {
        "hashed_key_event": {
            "redis": true
        },
        "key_event": {
            "redis": true
        }
    },
    "hybrid_enabled": true
}
HTTP 200
[Captures]
org_id: jsonpath "$.Meta"
[Asserts]
status == 200

# Create default user
POST http://tyk-dashboard:3000/admin/users/
Content-Type: application/json
admin-auth: {{admin_secret}}
{
  "org_id": "{{org_id}}",
  "first_name": "Tyk",
  "last_name": "Trial",
  "email_address": "developer@tyk.io",
  "active": true,
  "user_permissions": { "IsAdmin": "admin" }
}
HTTP 200
[Captures]
user_id: jsonpath "$.Meta.id"
user_api_key: jsonpath "$.Meta.access_key"
[Asserts]
status == 200

# Reset User Password
POST http://tyk-dashboard:3000/api/users/{{user_id}}/actions/reset
Content-Type: application/json
authorization: {{user_api_key}}
{
  "new_password":"specialpassword",
  "user_permissions": { "IsAdmin": "admin" }
}
HTTP 200

# Import HTTPBingo OAS API
POST http://tyk-dashboard:3000/api/apis/oas
authorization: {{user_api_key}}
Content-Type: application/json
file,apis/tykoas-77f7e1f3ab3340335a2196fb27a4920f.json;
HTTP 200
[Captures]
httpbingo_api_id: jsonpath "$.ID"
[Asserts]
status == 200

# Import F1 OAS API
POST http://tyk-dashboard:3000/api/apis/oas
authorization: {{user_api_key}}
Content-Type: application/json
file,apis/tykoas-9cf3694bac08471d6990a7b16aeacb0a.json;
HTTP 200
[Captures]
f1_api_id: jsonpath "$.ID"
[Asserts]
status == 200

# Create Access-Only Policy for Test API (no rate limiting)
POST http://tyk-dashboard:3000/api/portal/policies/
Authorization: {{user_api_key}}
Content-Type: application/json
{
    "access_rights": {
        "{{httpbingo_api_id}}": {
            "allowed_urls": [],
            "api_id": "{{httpbingo_api_id}}",
            "api_name": "httpbingo API",
            "limit": null,
            "versions": [
                "Default"
            ]
        }
    },
    "active": true,
    "name": "HTTPBIN API Access",
    "org_id": "{{org_id}}",
    "per": -1,
    "rate": -1,
    "quota_max": -1,
    "quota_remaining": -1,
    "quota_renewal_rate": -1,
    "quota_renews": -1,
    "throttle_interval": -1,
    "throttle_retry_limit": -1,
    "tags": [],
    "allowance": 0,
    "auth_type": "other",
    "expires": 0,
    "key_expires_in": 0,
    "last_check": 0,
    "partitions": {
        "quota": false,
        "rate_limit": false,
        "complexity": false,
        "acl": true,
        "per_api": false
    }
}
HTTP 200
[Captures]
policy_id: jsonpath "$.Message"
[Asserts]
status == 200

# Create Sandbox Plan Policy with rate limiting (no access enforcement)
POST http://tyk-dashboard:3000/api/portal/policies/
Authorization: {{user_api_key}}
Content-Type: application/json
{
    "access_rights": {
        "{{httpbingo_api_id}}": {
            "allowed_urls": [],
            "api_id": "{{httpbingo_api_id}}",
            "api_name": "httpbingo API",
            "limit": null,
            "versions": [
                "Default"
            ]
        }
    },
    "active": true,
    "name": "Sandbox Plan",
    "org_id": "{{org_id}}",
    "per": 10,
    "rate": 3,
    "quota_max": -1,
    "quota_remaining": -1,
    "quota_renewal_rate": -1,
    "quota_renews": -1,
    "throttle_interval": -1,
    "throttle_retry_limit": -1,
    "tags": [],
    "allowance": 0,
    "auth_type": "other",
    "expires": 0,
    "key_expires_in": 0,
    "last_check": 0,
    "partitions": {
        "quota": true,
        "rate_limit": true,
        "complexity": false,
        "acl": false,
        "per_api": false
    }
}
HTTP 200
[Captures]
sandbox_policy_id: jsonpath "$.Message"
[Asserts]
status == 200

# Create Production Plan Policy with higher rate limiting
POST http://tyk-dashboard:3000/api/portal/policies/
Authorization: {{user_api_key}}
Content-Type: application/json
{
    "access_rights": {
        "{{httpbingo_api_id}}": {
            "allowed_urls": [],
            "api_id": "{{httpbingo_api_id}}",
            "api_name": "httpbingo API",
            "limit": null,
            "versions": [
                "Default"
            ]
        }
    },
    "active": true,
    "name": "Production Plan",
    "org_id": "{{org_id}}",
    "per": 60,
    "rate": 100,
    "quota_max": -1,
    "quota_remaining": -1,
    "quota_renewal_rate": -1,
    "quota_renews": -1,
    "throttle_interval": -1,
    "throttle_retry_limit": -1,
    "tags": [],
    "allowance": 0,
    "auth_type": "other",
    "expires": 0,
    "key_expires_in": 0,
    "last_check": 0,
    "partitions": {
        "quota": true,
        "rate_limit": true,
        "complexity": false,
        "acl": false,
        "per_api": false
    }
}
HTTP 200
[Captures]
production_policy_id: jsonpath "$.Message"
[Asserts]
status == 200

# Create F1 API Policy with rate limiting (4 calls per 15 seconds)
POST http://tyk-dashboard:3000/api/portal/policies/
Authorization: {{user_api_key}}
Content-Type: application/json
{
    "access_rights": {
        "{{f1_api_id}}": {
            "allowed_urls": [],
            "api_id": "{{f1_api_id}}",
            "api_name": "F1 API",
            "limit": null,
            "versions": [
                "Default"
            ]
        }
    },
    "active": true,
    "name": "F1 API access",
    "org_id": "{{org_id}}",
    "per": 15,
    "rate": 4,
    "quota_max": -1,
    "quota_remaining": -1,
    "quota_renewal_rate": -1,
    "quota_renews": -1,
    "throttle_interval": -1,
    "throttle_retry_limit": -1,
    "tags": [],
    "allowance": 0,
    "auth_type": "other",
    "expires": 0,
    "key_expires_in": 0,
    "last_check": 0
}
HTTP 200
[Captures]
f1_policy_id: jsonpath "$.Message"
[Asserts]
status == 200

# Update F1 API defaultPolicies with the created policy
PUT http://tyk-dashboard:3000/api/apis/oas/{{f1_api_id}}
authorization: {{user_api_key}}
Content-Type: application/json
{
  "components": {
    "securitySchemes": {
      "jwtAuth": {
        "bearerFormat": "JWT",
        "scheme": "bearer",
        "type": "http"
      }
    }
  },
  "info": {
    "title": "F1 API",
    "version": "1.0.0"
  },
  "openapi": "3.0.3",
  "paths": {},
  "security": [
    {
      "jwtAuth": []
    }
  ],
  "servers": [
    {
      "url": "http://localhost:8080/f1-api/"
    }
  ],
  "x-tyk-api-gateway": {
    "info": {
      "name": "F1 API",
      "state": {
        "active": true
      }
    },
    "middleware": {
      "global": {
        "contextVariables": {
          "enabled": true
        },
        "trafficLogs": {
          "enabled": true
        }
      }
    },
    "server": {
      "authentication": {
        "enabled": true,
        "securitySchemes": {
          "jwtAuth": {
            "defaultPolicies": [
              "{{f1_policy_id}}"
            ],
            "enabled": true,
            "header": {
              "enabled": true,
              "name": "Authorization"
            },
            "identityBaseField": "sub",
            "policyFieldName": "pol",
            "signingMethod": "hmac",
            "source": "dG9wc3BlY2lhbDI1NnNoYXJlZGJpdGxvbmdzZWNyZXQ="
          }
        }
      },
      "listenPath": {
        "strip": true,
        "value": "/f1-api/"
      }
    },
    "upstream": {
      "url": "https://f1api.dev/api"
    }
  }
}
HTTP 200
[Asserts]
status == 200

# Bootstrap Enterprise Portal with admin user
POST http://tyk-portal:3001/portal-api/bootstrap
Content-Type: application/json
{
    "username": "portaladmin@tyk.io",
    "password": "specialpassword",
    "first_name": "Admin",
    "last_name": "User"
}
HTTP 200
[Captures]
portal_token: jsonpath "$.data.api_token"
[Asserts]
status == 200

# Wait for portal to fully initialize after bootstrap
GET http://tyk-dashboard:3000/hello
[Options]
delay: 5000

# Check existing providers - test connection and auth
GET http://tyk-portal:3001/portal-api/providers
Accept: application/json
Authorization: {{portal_token}}

# Create Provider for Tyk Dashboard
POST http://tyk-portal:3001/portal-api/providers
Content-Type: application/json
Accept: application/json
Authorization: {{portal_token}}
{
  "Configuration": {
    "MetaData": "{\"URL\":\"http://tyk-dashboard:3000\",\"Secret\":\"{{user_api_key}}\",\"OrgID\":\"{{org_id}}\",\"Gateway\":\"\",\"PoliciesTags\":[],\"InsecureSkipVerify\":false}"
  },
  "Name": "Tyk Dashboard",
  "Type": "tyk-pro"
}
HTTP 201
[Captures]
provider_id: jsonpath "$.ID"
[Asserts]
status == 201

# Wait for provider to be fully created before synchronization
# GET http://tyk-dashboard:3000/hello
# [Options]
# delay: 3000

# Synchronize Provider Data (commented out - auto syncs)
# POST http://tyk-portal:3001/portal-api/providers/{{provider_id}}/synchronize
# Content-Type: application/json
# Accept: application/json
# Authorization: {{portal_token}}
# {}
# HTTP 200
# [Asserts]
# status == 200

# Wait for sync to complete before catalogue operations
GET http://tyk-dashboard:3000/hello
[Options]
delay: 3000

# Get public catalogue ID
GET http://tyk-portal:3001/portal-api/catalogues
Accept: application/json
Authorization: {{portal_token}}
HTTP 200
[Captures]
catalogue_id: jsonpath "$[0].ID"

# Get Portal Plans to find Plan IDs
GET http://tyk-portal:3001/portal-api/plans
Accept: application/json
Authorization: {{portal_token}}
HTTP 200
[Captures]
sandbox_plan_portal_id: jsonpath "$[0].ID"
production_plan_portal_id: jsonpath "$[1].ID"

# Get Portal Products to find Test API Product ID
GET http://tyk-portal:3001/portal-api/products
Accept: application/json
Authorization: {{portal_token}}
HTTP 200
[Captures]
test_product_id: jsonpath "$[0].ID"

# Update public catalogue with Plans and Products
PUT http://tyk-portal:3001/portal-api/catalogues/{{catalogue_id}}
Content-Type: application/json
Accept: application/json
Authorization: {{portal_token}}
{
  "Name": "Public catalogue",
  "NameWithSlug": "public-catalogue",
  "Plans": [
    {{sandbox_plan_portal_id}},
    {{production_plan_portal_id}}
  ],
  "Products": [
    {{test_product_id}}
  ],
  "VisibilityStatus": "Public"
}
HTTP 200
[Asserts]
status == 200