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

echo "✅ ¡Despliegue completado! En 1-2 minutos la web estará disponible en el balanceador."
