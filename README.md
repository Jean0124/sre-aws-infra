# SRE Challenge — Arquitectura Serverless AWS

Infraestructura como código para un servicio de procesamiento de datos serverless con caché Redis y persistencia S3.

## Diagrama de Arquitectura

```
                          ┌─────────────────────────────────────────────────────────────┐
                          │                        AWS VPC (10.0.0.0/16)                 │
                          │                                                               │
  Cliente HTTP            │   Subnets Públicas          Subnets Privadas                 │
      │                   │  ┌─────────────────┐       ┌──────────────────────────────┐  │
      │                   │  │  us-east-1a      │       │  us-east-1a  │  us-east-1b  │  │
      ▼                   │  │  10.0.0.0/24     │       │  10.0.10.0/24│ 10.0.11.0/24 │  │
 ┌──────────┐             │  │                 │       │              │              │  │
 │  API     │─────────────┤  │  NAT Gateway ◄──┼───────┤   Lambda     │              │  │
 │ Gateway  │             │  │  (EIP)          │       │   (Python)   │              │  │
 │ HTTP API │             │  └─────────────────┘       │      │       │              │  │
 └──────────┘             │  ┌─────────────────┐       │      ▼       │              │  │
      │                   │  │  us-east-1b      │       │   Redis                      │  │
      │  POST /process    │  │  10.0.1.0/24     │       │ (cache.t3.micro, 1 nodo)     │  │
      │                   │  │                 │       └──────────────────────────────┘  │
      │                   │  │  Internet GW ◄──┼────── tráfico de entrada               │
      │                   │  └─────────────────┘                                         │
      │                   │                         VPC Endpoint Gateway                 │
      │                   └─────────────────────────────────┬───────────────────────────┘
      │                                                      │
      └──────────────── flujo de datos ────────────────────► │
                                                             ▼
                                                      ┌─────────┐
                                                      │   S3    │
                                                      │ Bucket  │
                                                      │(privado)│
                                                      └─────────┘

Flujo de datos:
  Cliente → API Gateway → Lambda (VPC privada)
                               │
                               ├─ Redis HIT  → responde X-Cache: HIT
                               │
                               └─ Redis MISS → procesa → guarda S3 → escribe Redis TTL 60s → X-Cache: MISS
```

## Pre-requisitos

| Herramienta | Versión mínima |
|-------------|---------------|
| Terraform   | >= 1.3.0      |
| AWS CLI     | >= 2.0        |
| Python      | >= 3.10 (para empaquetar la Lambda localmente) |
| pip         | >= 23.0       |

**Permisos IAM requeridos en la cuenta AWS:**

- `ec2:*` (VPC, subnets, security groups)
- `elasticache:*`
- `lambda:*`
- `apigateway:*`
- `s3:*`
- `iam:CreateRole`, `iam:AttachRolePolicy`, `iam:PutRolePolicy`
- `logs:*`

## Despliegue

### 1. Clonar el repositorio

```bash
git clone https://github.com/Jean0124/sre-aws-infra.git
cd sre-aws-infra
```

### 2. Configurar credenciales AWS

```bash
export AWS_ACCESS_KEY_ID=<tu-access-key>
export AWS_SECRET_ACCESS_KEY=<tu-secret-key>
export AWS_DEFAULT_REGION=us-east-1
# o usa: aws configure
```

### 3. Ajustar variables (opcional)

Editar `terraform.tfvars`:

```hcl
aws_region  = "us-east-1"
project     = "sre-challenge"
environment = "dev"
vpc_cidr    = "10.0.0.0/16"
```

### 4. Desplegar

```bash
terraform init
terraform plan   # revisar cambios antes de aplicar
terraform apply  # confirmar con "yes"
```

El despliegue tarda aproximadamente **8–12 minutos** (el recurso más lento es ElastiCache Redis ~5 min).

### 5. Obtener el endpoint

```bash
terraform output api_endpoint
# Ejemplo: https://abc123.execute-api.us-east-1.amazonaws.com
```

## Verificación end-to-end

### Request 1 — debe retornar X-Cache: MISS

```bash
API_URL=$(terraform output -raw api_endpoint)

curl -i -X POST "${API_URL}/process" \
  -H "Content-Type: application/json" \
  -d '{"message": "hola mundo", "user": "sre-test"}'
```

Respuesta esperada:
```
HTTP/2 200
x-cache: MISS
content-type: application/json

{"original": {...}, "processed": {...}, "hash": "...", "s3_key": "results/2024-01-15/uuid.json"}
```

### Request 2 — mismo body, debe retornar X-Cache: HIT

```bash
curl -i -X POST "${API_URL}/process" \
  -H "Content-Type: application/json" \
  -d '{"message": "hola mundo", "user": "sre-test"}'
```

Respuesta esperada:
```
HTTP/2 200
x-cache: HIT
```

### Verificar objeto en S3

```bash
BUCKET=$(terraform output -raw s3_bucket_name)
aws s3 ls "s3://${BUCKET}/results/" --recursive
```

### Ver logs de Lambda en CloudWatch

```bash
FUNCTION=$(terraform output -raw lambda_function_name)
aws logs tail "/aws/lambda/${FUNCTION}" --follow
```

## Destruir infraestructura

```bash
terraform destroy
```

> ⚠️ Esto elimina **todos** los recursos incluyendo el bucket S3 y su contenido.

---

## Decisiones de diseño

### HTTP API vs REST API (API Gateway)

Se eligió **HTTP API (v2)** por las siguientes razones:

- **Costo:** ~$1.00/millón de requests vs ~$3.50 en REST API
- **Latencia:** menor overhead en la integración proxy con Lambda
- **CORS nativo:** se configura a nivel de API sin recursos adicionales
- **Throttling simplificado:** se aplica a nivel de stage en el `default_route_settings`

REST API se justificaría solo si se necesitara: API Keys con Usage Plans, request/response mapping con Velocity Templates, o integraciones con servicios distintos a Lambda/HTTP.

### Tipo de nodo Redis: cache.t3.micro

Para un ambiente de desarrollo/evaluación, `cache.t3.micro` es suficiente. En producción se consideraría `cache.r7g.large` para mayor memoria y rendimiento. El TTL de 60s evita acumulación de datos y el parámetro `snapshot_retention_limit = 0` deshabilita snapshots ya que Redis actúa únicamente como caché efímera.

### VPC Endpoint Gateway para S3

Se usa un **Gateway Endpoint** (no Interface Endpoint) para S3 porque:
- Es **gratuito** (los Interface Endpoints tienen costo por hora)
- El tráfico Lambda → S3 nunca sale a internet, va por la red interna de AWS
- Se añade automáticamente como ruta en la tabla de rutas privada

### Security Groups con mínimo privilegio

- SG de Lambda: solo permite egress a Redis (6379) y HTTPS (443) para el SDK de AWS
- SG de Redis: solo permite ingress desde el SG de Lambda, sin acceso público
- No hay reglas ingress en Lambda ya que es invocada por API Gateway, no por red directa

### Bucket Policy — doble capa de seguridad en S3

Se implementaron dos controles de acceso independientes sobre el bucket:

- **IAM Role Policy** (del lado del actor): le dice a Lambda qué acciones puede hacer en S3
- **Bucket Policy** (del lado del recurso): deniega `GetObject`, `PutObject` y `DeleteObject` a cualquier principal que no sea el rol IAM de Lambda

Esta doble capa garantiza que aunque otro recurso de la cuenta tuviera permisos IAM amplios, el bucket rechazaría sus peticiones. La policy se definió en `main.tf` en lugar del módulo S3 para evitar una dependencia circular (S3 necesita el ARN del rol Lambda, y Lambda necesita el ARN del bucket).

### Empaquetado de dependencias Lambda

La librería `redis` (cliente Python) se instala localmente con `pip` durante `terraform apply` usando un `null_resource` con trigger basado en MD5 del requirements.txt, lo que asegura que el paquete se regenera solo cuando cambian las dependencias o el handler.
