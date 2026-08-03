# 🧠 Conocimiento Base: Despliegue en AWS y Resolución de Errores

Este documento recopila los problemas encontrados durante la migración de local a AWS ECS y cómo se solucionaron, para servir como referencia futura.

## 1. Error 401 Unauthorized en el Backend (JWT Validation)
**Problema:** Al desplegar en AWS, las peticiones del CMS al Backend devolvían `401 Unauthorized` a pesar de enviar el token correcto. Además, los logs del backend mostraban `Connection refused`.
**Causa:** Spring Security estaba intentando validar la firma del token conectándose a `http://localhost:8180` (valor por defecto en `application.yml`) porque no recibía correctamente las variables de entorno de Keycloak. El token había sido emitido por el dominio del ALB de AWS, por lo que el `issuer` no coincidía, y el backend no podía descargar las claves públicas (JWKS).
**Solución:** 
Se inyectaron de forma explícita en `compute.tf` las variables necesarias para el backend:
```hcl
{ name = "KEYCLOAK_ISSUER_URI", value = "http://${aws_lb.main.dns_name}/realms/auren" },
{ name = "KEYCLOAK_JWK_URI", value = "http://${aws_lb.main.dns_name}/realms/auren/protocol/openid-connect/certs" }
```

## 2. Errores de CORS (Cross-Origin Resource Sharing)
**Problema:** Peticiones bloqueadas por política CORS en el navegador.
**Causa:** El backend (Spring Boot) y FastAPI (Analytics) no tenían el dominio del ALB en su lista de orígenes permitidos.
**Solución:** Se añadió la variable `CORS_ORIGINS` en `compute.tf` para incluir el DNS del ALB y propagarla a todos los contenedores:
```hcl
{ name = "CORS_ORIGINS", value = "http://${aws_lb.main.dns_name},http://localhost:3000" }
```

## 3. Bucle infinito de redirecciones en el Login de Keycloak
**Problema:** Al acceder a la consola de administración de Keycloak, el navegador entraba en un bucle infinito o daba error de conexión al hacer logout.
**Causa:** El proxy de AWS ALB modifica las cabeceras. Keycloak necesita saber que está detrás de un proxy (`X-Forwarded-For`, etc.) para generar las URLs correctamente.
**Solución:** Se configuró Keycloak en `compute.tf` con:
```hcl
{ name = "KC_PROXY_HEADERS", value = "xforwarded" },
{ name = "KC_HOSTNAME_STRICT", value = "false" }
```

## 4. Despliegue de Analytics (Python/FastAPI)
**Problema:** El CMS daba error al cargar las gráficas porque intentaba acceder a `localhost:8001`. El servicio de analytics no estaba en Terraform.
**Solución:** 
1. Se creó toda la infraestructura en Terraform (ECR, Target Group, ECS Task, ECS Service).
2. Se enrutó el tráfico en el ALB: `/v1/analytics/*`, `/v1/observations/*`, `/v1/copilot/*` se dirigen al contenedor de Python (prioridad 75, antes que la regla comodín del backend).
3. Se actualizó el cliente en el CMS (`analytics-client.ts`) para usar rutas relativas si está en el navegador, delegando el enrutamiento al ALB.
4. Se añadieron `PyJWT` y `cryptography` a `requirements.txt` ya que faltaban para validar tokens.

## 5. Prioridad de Reglas en el ALB (Routing)
**Problema potencial:** Colisión de rutas (ej. `/api/auth/*` del CMS vs `/api/*` del Backend).
**Solución:** Se establecieron prioridades estrictas en los `aws_lb_listener_rule`:
- Prioridad 50: `NextAuth` del CMS (`/api/auth/*`) -> Va al CMS
- Prioridad 75: `Analytics` (`/v1/analytics/*`, etc.) -> Va a Python
- Prioridad 100: `Backend` (`/api/*`, `/ws/*`) -> Va a Spring Boot Java
- Prioridad 200: `Keycloak` (`/auth/*`, `/realms/*`, etc.) -> Va a Keycloak
