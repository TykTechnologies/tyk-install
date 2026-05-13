#!/bin/bash

# ============================================================================
# CONFIGURATION
# ============================================================================
BOOTSTRAP_MARKER="./bootstrap-output/.bootstrap_completed"
CREDS_FILE="./bootstrap-output/bootstrap-credentials.txt"
#### environment vars to set if running script standalone not through docker-compose
# TYK_LICENSE_KEY=
# DASHBOARD_URL=http://localhost:3000
# GATEWAY_URL=https://localhost:8080
# PORTAL_URL=http://localhost:3001
# ADMIN_SECRET=admin-secret
# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

# ============================================================================
# UTILITY FUNCTIONS
# ============================================================================

log_success() {
    echo -e "${GREEN}✓ $1${NC}"
}

log_warning() {
    echo -e "${YELLOW}⚠ $1${NC}"
}

log_error() {
    echo -e "${RED}ERROR: $1${NC}"
}

log_info() {
    echo "  $1"
}

# ============================================================================
# BOOTSTRAP CHECK
# ============================================================================
check_if_already_bootstrapped() {
    # Create bootstrap-output directory if it doesn't exist
    mkdir -p "$(dirname "$BOOTSTRAP_MARKER")"
    
    if [ -f "$BOOTSTRAP_MARKER" ]; then
        log_warning "Bootstrap already completed on: $(cat $BOOTSTRAP_MARKER)"
        echo ""
        
        # Load existing credentials
        if [ -f "$CREDS_FILE" ]; then
            log_info "Loading existing credentials..."
            user_api_key=$(grep "Dash Key:" "$CREDS_FILE" | sed 's/.*Dash Key: //' | tr -d ' \n\r')
            orgId=$(grep "Org ID:" "$CREDS_FILE" | sed 's/.*Org ID: //' | tr -d ' \n\r')
            apiId=$(grep "API ID:" "$CREDS_FILE" | sed 's/.*API ID: //' | tr -d ' \n\r')
            actualKey=$(grep "Test API Key:" "$CREDS_FILE" | sed 's/.*Test API Key: //' | tr -d ' \n\r')
            portal_token=$(grep "Token:" "$CREDS_FILE" | sed 's/.*Token: //' | tr -d ' \n\r')
            
            log_success "Credentials loaded from file"
            echo ""
        else
            log_error "Bootstrap marker exists but credentials file not found"
            echo ""
            echo "To restart: docker-compose down -v && rm -rf ./output/"
        fi
        
    fi
}
verify_license_key() {
    if [ -z "$TYK_LICENSE_KEY" ]; then
        log_error "TYK_LICENSE_KEY not set"
        exit 1
    fi
    log_success "License key found"
    echo ""
}

# ============================================================================
# WAIT FOR SERVICES
# ============================================================================

wait_for_dashboard() {
    echo "Waiting for Tyk Dashboard..."
    local status=""
    local attempt=0
    local max_attempts=30

    while [ "$status" != "200" ] && [ $attempt -le $max_attempts ]; do
        status=$(curl -s -o /dev/null -w "%{http_code}" ${DASHBOARD_URL}/hello)
        if [ "$status" != "200" ]; then
            log_info "Attempt $((attempt + 1))/$max_attempts - Status: $status"
            sleep 2
        fi
        attempt=$((attempt + 1))
    done

    if [ "$status" != "200" ]; then
        log_error "Dashboard not ready after $max_attempts attempts"
        exit 1
    fi

    log_success "Dashboard is ready"
    echo ""
}

wait_for_portal() {
    echo "Waiting for Developer Portal..."
    local status=""
    local attempt=0
    local max_attempts=20

    while [ "$status" != "200" ] && [ $attempt -le $max_attempts ]; do
        status=$(curl -s -o /dev/null -w "%{http_code}" ${PORTAL_URL}/ready)
        if [ "$status" != "200" ]; then
            log_info "Attempt $((attempt + 1))/$max_attempts"
            sleep 3
        fi
        attempt=$((attempt + 1))
    done

    if [ "$status" != "200" ]; then
        log_warning "Portal not ready (Status: $status)"
        return 1
    fi

    log_success "Portal is ready"
    return 0
}

# ============================================================================
# ORGANIZATION MANAGEMENT
# ============================================================================

get_or_create_organization() {
    echo "Managing organization..."
    
    # Check for existing organizations using admin endpoint
    local existingOrgs=$(curl -s --location "${DASHBOARD_URL}/admin/organisations/" \
        --header "admin-auth: ${ADMIN_SECRET}")
    
    # Extract organization ID using Meta field 
    orgId=$(echo "$existingOrgs" | grep -o '"id":"[^"]*"' | head -1 | cut -d'"' -f4)
    
    if [ -n "$orgId" ]; then
        log_info "Using existing organization: $orgId"
    else
        log_info "Creating new organization..."
        local createOrgResponse=$(curl -s --location "${DASHBOARD_URL}/admin/organisations/" \
            --header "admin-auth: ${ADMIN_SECRET}" \
            --header 'Content-Type: application/json' \
            --data '{
                "owner_name": "Demo Organization",
                "cname_enabled": true,
                "event_options": {
                    "hashed_key_event": {"redis": true},
                    "key_event": {"redis": true}
                }
            }')
        
        # Extract using Meta field 
        orgId=$(echo "$createOrgResponse" | grep -o '"Meta":"[^"]*"' | cut -d'"' -f4)
        
        if [ -z "$orgId" ]; then
            log_error "Failed to create organization"
            echo "Response: $createOrgResponse"
            exit 1
        fi
        
        log_info "Organization created: $orgId"
    fi
    
    log_success "Organization ready: $orgId"
    echo ""
}

# ============================================================================
# USER MANAGEMENT
# ============================================================================

get_or_create_admin_user() {
    echo "Managing admin user..."
    
    # Check for existing users using admin endpoint
    local existingUsers=$(curl -s --location "${DASHBOARD_URL}/api/users/" \
        --header "authorization: ${user_api_key}")
    echo $user_api_key
    # Search for user by email 
    user_id=$(echo "$existingUsers" | grep -B5 "admin@example.com" | grep -o '"id":"[^"]*"' | head -1 | cut -d'"' -f4)
    
    if [ -n "$user_id" ]; then
        log_info "Using existing admin user: $user_id"
        # Extract API key from existing user
        user_api_key=$(echo "$existingUsers" | grep -A10 "\"id\":\"$user_id\"" | grep -o '"access_key":"[^"]*"' | head -1 | cut -d'"' -f4)
    else
        log_info "Creating new admin user..."
        local createUserResponse=$(curl -s --location "${DASHBOARD_URL}/admin/users/" \
            --header 'Content-Type: application/json' \
            --header "admin-auth: ${ADMIN_SECRET}" \
            --data '{
                "org_id": "'$orgId'",
                "first_name": "Admin",
                "last_name": "User",
                "email_address": "admin@example.com",
                "active": true,
                "user_permissions": { "IsAdmin": "admin" }
            }')
        # Extract id and access_key 
        user_id=$(echo "$createUserResponse" | grep -o '"id":"[^"]*"' | cut -d'"' -f4)
        user_api_key=$(echo "$createUserResponse" | grep -o '"access_key":"[^"]*"' | cut -d'"' -f4)
        
        if [ -z "$user_id" ] || [ -z "$user_api_key" ]; then
            log_error "Failed to create user"
            echo "Response: $createUserResponse"
            exit 1
        fi
        
        log_info "Setting password..."
        curl -s -o /dev/null --location "${DASHBOARD_URL}/api/users/${user_id}/actions/reset" \
            --header 'Content-Type: application/json' \
            --header "authorization: ${user_api_key}" \
            --data '{
                "new_password": "topsecret123",
                "user_permissions": { "IsAdmin": "admin" }
            }'
    fi
    
    log_success "Admin user ready: $user_id"
    echo ""
}

# ============================================================================
# API MANAGEMENT
# ============================================================================

get_or_create_test_api() {
    echo "Managing test API..."
    
    # Check for existing APIs using user API key
    local existingApis=$(curl -s --location "${DASHBOARD_URL}/api/apis" \
        --header "authorization: ${user_api_key}")
    
    # Search by API name
    apiId=$(echo "$existingApis" | grep -B10 "Httpbin Test API" | grep -o '"api_id":"[^"]*"' | head -1 | cut -d'"' -f4)
    
    if [ -n "$apiId" ]; then
        log_info "Using existing API: $apiId"
    else
        log_info "Creating new API..."
        local createApiResponse=$(curl -s --location "${DASHBOARD_URL}/api/apis/oas" \
            --header "authorization: ${user_api_key}" \
            --header 'Content-Type: application/json' \
            --data '{
          "info": {
            "description": "Test API using httpbin.org for PoC demonstration",
            "title": "Httpbin Test API",
            "version": "1.0.0"
          },
          "openapi": "3.0.3",
          "servers": [{"url": "https://httpbingo.org/"}],
          "security": [{"authToken": []}],
          "paths": {
            "/anything/{path}": {
              "get": {
                "operationId": "anythingRequest",
                "parameters": [{"in": "path", "name": "path", "required": true, "schema": {"type": "string"}}],
                "responses": {"200": {"description": "Successful response"}},
                "summary": "Returns anything passed in request"
              }
            },
            "/get": {
              "get": {
                "operationId": "getRequest",
                "responses": {"200": {"description": "Successful response"}},
                "summary": "HTTP GET test endpoint"
              }
            },
            "/post": {
              "post": {
                "operationId": "postRequest",
                "responses": {"200": {"description": "Successful response"}},
                "summary": "HTTP POST test endpoint"
              }
            }
          },
          "components": {
            "securitySchemes": {
              "authToken": {"type": "apiKey", "in": "header", "name": "Authorization"}
            }
          },
          "x-tyk-api-gateway": {
            "info": {
              "name": "Httpbin Test API (OAS)",
              "state": {"active": true, "internal": false}
            },
            "upstream": {
              "proxy": {"enabled": false, "url": ""},
              "url": "https://httpbingo.org/"
            },
            "server": {
              "authentication": {
                "enabled": true,
                "securitySchemes": {"authToken": {"enabled": true}}
              },
              "listenPath": {"value": "/httpbin/", "strip": true}
            },
            "middleware": {
              "global": {"trafficLogs": {"enabled": true}}
            }
          }
        }')
        
        # Verify API creation was successful using Status field 
        local apiStatus=$(echo "$createApiResponse" | grep -o '"Status":"[^"]*"' | cut -d'"' -f4)
        
        if [ "$apiStatus" != "OK" ]; then
            log_error "Failed to create API (Status: $apiStatus)"
            echo "Response: $createApiResponse"
            exit 1
        fi
        
        # Extract API ID using capital ID field 
        apiId=$(echo "$createApiResponse" | grep -o '"ID":"[^"]*"' | cut -d'"' -f4)
        
        if [ -z "$apiId" ]; then
            log_error "Could not extract API ID from response"
            echo "Response: $createApiResponse"
            exit 1
        fi
        
        log_info "API created: $apiId"
    fi
    
    log_success "Test API ready: $apiId"
    echo ""
}

# ============================================================================
# POLICY MANAGEMENT
# ============================================================================

get_or_create_policy() {
    echo "Managing policy..."
    
    # Check for existing policies
    local existingPolicies=$(curl -s --location "${DASHBOARD_URL}/api/portal/policies/" \
        --header "Authorization: ${user_api_key}")
    
    # Search for policy by name
    policyId=$(echo "$existingPolicies" | grep -B5 "Test API Policy" | grep -o '"_id":"[^"]*"' | head -1 | cut -d'"' -f4)
    if [ -n "$policyId" ]; then
        log_info "Using existing policy: $policyId"
    else
        log_info "Creating new policy..."
        local createPolicyResponse=$(curl -s --location "${DASHBOARD_URL}/api/portal/policies/" \
            --header "Authorization: ${user_api_key}" \
            --header 'Content-Type: application/json' \
            --data '{
                "access_rights": {
                    "'$apiId'": {
                        "allowed_urls": [],
                        "api_id": "'$apiId'",
                        "api_name": "Httpbin Test API",
                        "versions": ["Default"]
                    }
                },
                "active": true,
                "name": "Test API Policy",
                "org_id": "'$orgId'",
                "last_check": 0,
                "allowance": 1000,
                "rate": 1000,
                "per": 60,
                "throttle_interval": -1,
                "throttle_retry_limit": -1,
                "expires": 0,
                "quota_max": -1,
                "quota_renews": 1587524070,
                "quota_remaining": -1,
                "quota_renewal_rate": -1
            }')
        
        # Extract policy ID 
        policyId=$(echo "$createPolicyResponse" | grep -o '"Message":"[^"]*"' | cut -d'"' -f4)
                
        log_info "Policy created: $policyId"
    fi
    
    log_success "Policy ready: $policyId"
    echo ""
}

# ============================================================================
# API KEY MANAGEMENT
# ============================================================================

get_or_create_api_key() {
    echo "Managing test API key..."
    
    local keyAlias="test-api-key-123"
    
    # Check for existing API keys 
    local existingKeys=$(curl -s --location "${DASHBOARD_URL}/api/keys/detailed" \
        --header "authorization: ${user_api_key}")
    # Search for key by alias
    actualKey=$(echo "$existingKeys" | grep -B10 "$keyAlias" | grep -o '"key_id":"[^"]*"' | head -1 | cut -d'"' -f4)
    
    if [ -n "$actualKey" ]; then
        log_info "Using existing API key: $actualKey"
    else
        log_info "Creating new API key..."
        local createKeyResponse=$(curl -s --location "${DASHBOARD_URL}/api/keys" \
            --header "authorization: ${user_api_key}" \
            --header 'Content-Type: application/json' \
            --data '{
                "alias": "'$keyAlias'",
                "org_id": "'$orgId'",
                "expires": 0,
                "allowance": 1000,
                "per": 60,
                "quota_max": -1,
                "quota_renews": 0,
                "quota_remaining": -1,
                "quota_renewal_rate": -1,
                "rate": 1000,
                "per": 60,
                "throttle_interval": -1,
                "throttle_retry_limit": -1,
                "access_rights": {
                    "'$apiId'": {
                        "api_id": "'$apiId'",
                        "api_name": "Httpbin Test API (OAS)",
                        "versions": ["Default"]
                    }
                },
                "meta_data": {
                    "description": "Test API key for PoC demonstration"
                },
                "is_inactive": false
            }')

        # Extract the actual key using key_id field 
        actualKey=$(echo "$createKeyResponse" | grep -o '"key_id":"[^"]*"' | cut -d'"' -f4)
        log_info "API key created"
    fi
    
    log_success "API key ready"
    echo ""
}

# ============================================================================
# PORTAL MANAGEMENT
# ============================================================================

bootstrap_portal() {
    echo "Managing Developer Portal..."
    
    if ! wait_for_portal; then
        log_warning "Portal not available, skipping..."
        return
    fi
    
    log_info "Bootstrapping portal..."
    
    if [ -n "$portal_token" ]; then
        log_warning "Portal already bootstrapped"
    else
        local portal_response=$(curl -s "${PORTAL_URL}/portal-api/bootstrap" \
            -H 'Content-Type: application/json' \
            --data '{
                "username": "portal-admin@example.com",
                "password": "portalpass123",
                "first_name": "Portal",
                "last_name": "Admin"
            }')
        
        portal_token=$(echo "$portal_response" | grep -o '"api_token":"[^"]*"' | cut -d'"' -f4)
        
        if [ -z "$portal_token" ]; then
            log_warning "Portal bootstrapping may have failed"
            log_info "Response: $portal_response"
            log_info "You can bootstrap manually at: ${PORTAL_URL}/portal-api/bootstrap"
            return
        fi

        log_info "Portal bootstrapped successfully"

    fi

    configure_portal_provider
    log_success "Portal ready"
    echo ""
}

configure_portal_provider() {
    log_info "Configuring portal provider..."
    
    local attempt=0
    local max_attempts=3
    local provider_success=false
    
    while [ $attempt -lt $max_attempts ] && [ "$provider_success" = false ]; do
        if [ $attempt -gt 0 ]; then
            log_info "Retrying configuration... Attempt $((attempt + 1))/$max_attempts"
            sleep 5
        fi
        
        local provider_response=$(curl -s "${PORTAL_URL}/portal-api/providers" \
            -H "Authorization: ${portal_token}" \
            -H "Content-Type: application/json" \
            --data '{
                "Name": "Tyk Dashboard",
                "Type": "tyk-pro",
                "Configuration": {
                    "MetaData": "{\"URL\":\"http://tyk-dashboard:3000\",\"Secret\":\"'${user_api_key}'\",\"OrgID\":\"'${orgId}'\",\"InsecureSkipVerify\":false}"
                }
            }')
        
        # Check for successful JSON response containing ID field 
        if echo "$provider_response" | grep -q '"ID":'; then
            provider_success=true
            log_info "Provider configured successfully"
        else
            attempt=$((attempt + 1))
        fi
    done
    
    if [ "$provider_success" = false ]; then
        log_warning "Failed to configure Portal provider after $max_attempts attempts"
        log_info "Last response: ${provider_response}"
    fi
}

# ============================================================================
# CREDENTIALS MANAGEMENT
# ============================================================================

save_credentials() {
    # Create bootstrap-output directory if it doesn't exist
    mkdir -p "$(dirname "$CREDS_FILE")"
    
    local CREDS_CONTENT=$(cat << EOF
======================================================================
✓ Bootstrap Complete! SAVE THE FOLLOWING INFO
======================================================================

Access URLs (replace <host> with your server IP or localhost):
  Dashboard: http://<host>:3000
  Gateway:   http://<host>:8080
  Portal:    http://<host>:3001

Dashboard Credentials:
  Email:    admin@example.com
  Password: topsecret123

Portal Admin Credentials:
  Email:    portal-admin@example.com
  Password: portalpass123
  Token:    ${portal_token}

API Testing:
  Test API Key: ${actualKey}
  Test Command: curl http://<host>:8080/httpbin/get -H "Authorization: ${actualKey}"

Dashboard API Credentials:
  Dash Key: ${user_api_key}
  Org ID:  ${orgId}
  API ID:  ${apiId}

For Tyk Sync, use the Dashboard API Key above
======================================================================
Saved to: bootstrap-output/bootstrap-credentials.txt
EOF
)
    
    echo "$CREDS_CONTENT" > "$CREDS_FILE"
    echo "$(date -u +"%Y-%m-%d %H:%M:%S UTC")" > "$BOOTSTRAP_MARKER"
    
    echo ""
    echo "$CREDS_CONTENT"
    echo ""
    log_success "Bootstrap completed successfully!"
}

# ============================================================================
# MAIN EXECUTION
# ============================================================================

main() {
    check_if_already_bootstrapped
    verify_license_key
    wait_for_dashboard
    
    get_or_create_organization
    get_or_create_admin_user
    get_or_create_test_api
    get_or_create_policy
    get_or_create_api_key
    bootstrap_portal

    save_credentials

}

# Run main function
main