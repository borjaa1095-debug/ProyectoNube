#!/bin/bash
set -euo pipefail
export AWS_PAGER=""

REGION="us-east-1"
SUBNET_ID="subnet-06bab13b51f966b78"
VPC_ID="vpc-0c8a7ec10e2db07c2"
MI_IP="90.69.148.194/32"
ALUMNO="Borja Martínez"

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
USER_DATA="$SCRIPT_DIR/user-data1.sh"

if [[ ! -r "$USER_DATA" ]]; then
  echo "Falta user-data1.sh junto a desplegar.sh." >&2
  exit 1
fi

# Busca el grupo en la VPC del proyecto.
SG_ID=$(aws ec2 describe-security-groups --region "$REGION" \
  --filters "Name=vpc-id,Values=$VPC_ID" \
            "Name=group-name,Values=libreria-web-cli-sg" \
  --query 'SecurityGroups[0].GroupId' --output text)

if [[ "$SG_ID" == "None" ]]; then
  SG_ID=$(aws ec2 create-security-group --region "$REGION" \
    --group-name libreria-web-cli-sg \
    --description "Web Libreria Tinta (CLI)" \
    --vpc-id "$VPC_ID" \
    --query 'GroupId' --output text)
fi

# Consulta las reglas antes de añadirlas para evitar duplicados.
HTTP_RULE=$(aws ec2 describe-security-group-rules --region "$REGION" \
  --filters "Name=group-id,Values=$SG_ID" \
  --query "SecurityGroupRules[?IsEgress==\`false\` && IpProtocol=='tcp' && FromPort==\`80\` && ToPort==\`80\` && CidrIpv4=='0.0.0.0/0'] | [0].SecurityGroupRuleId" \
  --output text)

if [[ "$HTTP_RULE" == "None" ]]; then
  aws ec2 authorize-security-group-ingress --region "$REGION" \
    --group-id "$SG_ID" --protocol tcp --port 80 --cidr 0.0.0.0/0 \
    >/dev/null
fi

SSH_RULE=$(aws ec2 describe-security-group-rules --region "$REGION" \
  --filters "Name=group-id,Values=$SG_ID" \
  --query "SecurityGroupRules[?IsEgress==\`false\` && IpProtocol=='tcp' && FromPort==\`22\` && ToPort==\`22\` && CidrIpv4!=\`null\`] | [0].[SecurityGroupRuleId,CidrIpv4]" \
  --output text)

if [[ "$SSH_RULE" == "None" ]]; then
  aws ec2 authorize-security-group-ingress --region "$REGION" \
    --group-id "$SG_ID" --protocol tcp --port 22 --cidr "$MI_IP" \
    >/dev/null
else
  read -r SSH_RULE_ID SSH_CIDR <<< "$SSH_RULE"

  if [[ "$SSH_CIDR" != "$MI_IP" ]]; then
    aws ec2 modify-security-group-rules --region "$REGION" \
      --group-id "$SG_ID" \
      --security-group-rules \
      "SecurityGroupRuleId=$SSH_RULE_ID,SecurityGroupRule={IpProtocol=tcp,FromPort=22,ToPort=22,CidrIpv4=$MI_IP}" \
      >/dev/null
  fi
fi

# Busca una instancia creada en una ejecución anterior.
INSTANCE_INFO=$(aws ec2 describe-instances --region "$REGION" \
  --filters "Name=tag:Name,Values=libreria-web-cli" \
            "Name=vpc-id,Values=$VPC_ID" \
            "Name=subnet-id,Values=$SUBNET_ID" \
            "Name=instance-state-name,Values=pending,running,stopping,stopped" \
  --query 'Reservations[].Instances[] | [0].[InstanceId,State.Name]' \
  --output text)

if [[ "$INSTANCE_INFO" == "None" ]]; then
  AMI_ID=$(aws ssm get-parameters --region "$REGION" \
    --names /aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64 \
    --query 'Parameters[0].Value' --output text)

  INSTANCE_ID=$(aws ec2 run-instances --region "$REGION" \
    --image-id "$AMI_ID" \
    --instance-type t3.micro \
    --key-name vockey \
    --subnet-id "$SUBNET_ID" \
    --security-group-ids "$SG_ID" \
    --associate-public-ip-address \
    --user-data "file://$USER_DATA" \
    --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=libreria-web-cli},{Key=Proyecto,Value=P1},{Key=Alumno,Value=$ALUMNO}]" \
    --query 'Instances[0].InstanceId' --output text)

  echo "Instancia creada: $INSTANCE_ID"
else
  read -r INSTANCE_ID INSTANCE_STATE <<< "$INSTANCE_INFO"
  echo "Instancia reutilizada: $INSTANCE_ID"

  if [[ "$INSTANCE_STATE" == "stopping" ]]; then
    aws ec2 wait instance-stopped --region "$REGION" \
      --instance-ids "$INSTANCE_ID"
    INSTANCE_STATE="stopped"
  fi

  if [[ "$INSTANCE_STATE" == "stopped" ]]; then
    aws ec2 start-instances --region "$REGION" \
      --instance-ids "$INSTANCE_ID" >/dev/null
  fi
fi

aws ec2 wait instance-running --region "$REGION" \
  --instance-ids "$INSTANCE_ID"

IP=$(aws ec2 describe-instances --region "$REGION" \
  --instance-ids "$INSTANCE_ID" \
  --query 'Reservations[0].Instances[0].PublicIpAddress' \
  --output text)

if [[ -z "$IP" || "$IP" == "None" ]]; then
  echo "La instancia está en ejecución, pero aún no tiene IPv4 pública." >&2
  exit 1
fi

echo "Abre en el navegador: http://$IP"