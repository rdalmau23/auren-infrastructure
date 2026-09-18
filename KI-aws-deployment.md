# Knowledge Base: AWS Deployment & Troubleshooting

This document captures the issues encountered during the migration from local Docker to AWS ECS and how each was resolved, serving as a reference for future deployments.

## 1. 401 Unauthorized on the Backend (JWT Validation)
**Problem:** After deploying to AWS, requests from the CMS to the Backend returned `401 Unauthorized` despite sending a valid token. Backend logs showed `Connection refused`.
**Root Cause:** Spring Security was attempting to validate the token signature by connecting to `http://localhost:8180` (the default value in `application.yml`) because it was not receiving the Keycloak environment variables correctly. The token had been issued by the AWS ALB domain, so the `issuer` claim did not match, and the backend could not download the public keys (JWKS).
**Fix:** 
The required environment variables were explicitly injected into the backend task definition in `compute.tf`:
```hcl
{ name = "KEYCLOAK_ISSUER_URI", value = "http://${aws_lb.main.dns_name}/realms/auren" },
{ name = "KEYCLOAK_JWK_URI", value = "http://${aws_lb.main.dns_name}/realms/auren/protocol/openid-connect/certs" }
```

## 2. CORS Errors (Cross-Origin Resource Sharing)
**Problem:** Browser requests were blocked by CORS policy.
**Root Cause:** The backend (Spring Boot) and FastAPI (Analytics) did not have the ALB domain in their list of allowed origins.
**Fix:** A `CORS_ORIGINS` environment variable was added in `compute.tf` to include the ALB DNS and propagated to all containers:
```hcl
{ name = "CORS_ORIGINS", value = "http://${aws_lb.main.dns_name},http://localhost:3000" }
```

## 3. Infinite Redirect Loop on Keycloak Login
**Problem:** When accessing the Keycloak admin console, the browser entered an infinite redirect loop or threw a connection error on logout.
**Root Cause:** The AWS ALB proxy modifies request headers. Keycloak needs to know it is behind a reverse proxy (`X-Forwarded-For`, etc.) to generate URLs correctly.
**Fix:** Keycloak was configured in `compute.tf` with the appropriate proxy settings:
```hcl
{ name = "KC_PROXY_HEADERS", value = "xforwarded" },
{ name = "KC_HOSTNAME_STRICT", value = "false" }
```

## 4. Analytics Service Deployment (Python/FastAPI)
**Problem:** The CMS threw errors when loading charts because it was attempting to reach `localhost:8001`. The analytics service had not been provisioned in Terraform.
**Fix:** 
1. Full infrastructure was created in Terraform (ECR repository, Target Group, ECS Task Definition, ECS Service).
2. Traffic was routed at the ALB: `/v1/analytics/*`, `/v1/observations/*`, `/v1/copilot/*` are directed to the Python container (priority 75, evaluated before the backend wildcard rule).
3. The CMS client (`analytics-client.ts`) was updated to use relative paths when running in the browser, delegating routing to the ALB.
4. `PyJWT` and `cryptography` were added to `requirements.txt` as they were missing for token validation.

## 5. ALB Listener Rule Priority (Routing)
**Potential Problem:** Path collision between overlapping routes (e.g., `/api/auth/*` for CMS vs `/api/*` for Backend).
**Fix:** Strict priorities were established in the `aws_lb_listener_rule` resources:
- Priority 50: CMS `NextAuth` (`/api/auth/*`) → routes to CMS
- Priority 75: `Analytics` (`/v1/analytics/*`, etc.) → routes to Python
- Priority 100: `Backend` (`/api/*`, `/ws/*`) → routes to Spring Boot Java
- Priority 200: `Keycloak` (`/auth/*`, `/realms/*`, etc.) → routes to Keycloak
