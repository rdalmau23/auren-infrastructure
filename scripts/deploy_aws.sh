#!/bin/bash
set -e

# Configuración obtenida de tu AWS
AWS_ACCOUNT_ID="423535493684"
AWS_REGION="eu-west-1"
PROJECT="auren"
ENV="preprod"

# URLs de los Repositorios (sacadas del output de Terraform)
ECR_REGISTRY="${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com"
ECR_BACKEND="${ECR_REGISTRY}/${PROJECT}-${ENV}-backend"
ECR_CMS="${ECR_REGISTRY}/${PROJECT}-${ENV}-cms"
ECR_KEYCLOAK="${ECR_REGISTRY}/${PROJECT}-${ENV}-keycloak"
ECR_ANALYTICS="${ECR_REGISTRY}/${PROJECT}-${ENV}-analytics"

echo "🔐 Iniciando sesión en AWS ECR..."
aws ecr get-login-password --region $AWS_REGION | docker login --username AWS --password-stdin $ECR_REGISTRY

# NOTA: Usamos --platform linux/amd64 porque los Mac modernos usan ARM (M1/M2), 
# pero los servidores de AWS Fargate por defecto son Intel/AMD (x86_64).

echo "🚀 Construyendo y subiendo Backend..."
cd ../../auren-backend
docker build --platform linux/amd64 -t $ECR_BACKEND:latest .
docker push $ECR_BACKEND:latest

echo "🚀 Construyendo y subiendo Analytics..."
cd ../auren-analytics
docker build --platform linux/amd64 -t $ECR_ANALYTICS:latest .
docker push $ECR_ANALYTICS:latest

echo "🚀 Construyendo y subiendo CMS..."
cd ../auren-cms
cp -R ../auren-shared ./auren-shared
docker build --platform linux/amd64 -t $ECR_CMS:latest .
rm -rf ./auren-shared
docker push $ECR_CMS:latest

echo "🚀 Construyendo y subiendo Keycloak (con el realm inyectado)..."
cd ../auren-infrastructure/docker/keycloak
docker build --platform linux/amd64 -t $ECR_KEYCLOAK:latest .
docker push $ECR_KEYCLOAK:latest

echo "🔄 Avisando a los servidores (ECS) para que descarguen y arranquen las nuevas imágenes..."
aws ecs update-service --cluster ${PROJECT}-${ENV}-cluster --service ${PROJECT}-${ENV}-backend-service --force-new-deployment --region $AWS_REGION > /dev/null
aws ecs update-service --cluster ${PROJECT}-${ENV}-cluster --service ${PROJECT}-${ENV}-analytics-service --force-new-deployment --region $AWS_REGION > /dev/null
aws ecs update-service --cluster ${PROJECT}-${ENV}-cluster --service ${PROJECT}-${ENV}-cms-service --force-new-deployment --region $AWS_REGION > /dev/null
aws ecs update-service --cluster ${PROJECT}-${ENV}-cluster --service ${PROJECT}-${ENV}-keycloak-service --force-new-deployment --region $AWS_REGION > /dev/null

echo "⏳ Esperando a que Keycloak esté disponible para configurar la seguridad (puede tardar 2-3 minutos)..."
ALB_DNS=$(aws elbv2 describe-load-balancers --names ${PROJECT}-${ENV}-alb --region $AWS_REGION --query 'LoadBalancers[0].DNSName' --output text)
ALB_URL="http://$ALB_DNS"

for i in {1..40}; do
  if curl -s -I "$ALB_URL/admin/" | grep -q "302 Found\|200 OK"; then
    echo "✅ Keycloak está online. Configurando Redirect URIs en el CMS..."
    TOKEN=$(curl -s -d "client_id=admin-cli" -d "username=superadmin" -d "password=Rdc04123@" -d "grant_type=password" "$ALB_URL/realms/master/protocol/openid-connect/token" | grep -o '"access_token":"[^"]*' | grep -o '[^"]*$')
    if [ ! -z "$TOKEN" ]; then
      CLIENT_UUID=$(curl -s -H "Authorization: Bearer $TOKEN" "$ALB_URL/admin/realms/auren/clients?clientId=auren-cms" | grep -o '"id":"[^"]*' | head -n 1 | grep -o '[^"]*$')
      if [ ! -z "$CLIENT_UUID" ]; then
        CLIENT_JSON=$(curl -s -H "Authorization: Bearer $TOKEN" "$ALB_URL/admin/realms/auren/clients/$CLIENT_UUID")
        MODIFIED_JSON=$(echo "$CLIENT_JSON" | sed "s/\"redirectUris\":\[[^]]*\]/\"redirectUris\":\[\"http:\/\/localhost:3000\/*\",\"$ALB_URL\/*\"\]/")
        curl -s -o /dev/null -X PUT -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" -d "$MODIFIED_JSON" "$ALB_URL/admin/realms/auren/clients/$CLIENT_UUID"
        echo "✅ Configuración de Keycloak parcheada automáticamente para $ALB_URL"
      fi
    fi
    break
  fi
  sleep 10
done

echo "✅ ¡Despliegue completamente automatizado finalizado! La plataforma está lista."
