#!/bin/bash

# --- Variables de Red ---
RESOURCE_GROUP="rg-webapp-estudiantes2"
LOCATION="eastus"
VNET_NAME="vnet-principal"
SUBNET_APP_NAME="snet-aplicacion"
SUBNET_GW_NAME="snet-gateway"
VM_NAME="vm-servidor-web"
PUBLIC_IP_NAME="pip-gateway"
GW_NAME="appgw-principal"
NSG_NAME="nsg-servidor-web"
VM_IMAGE="Ubuntu2204"


# 1. Crear Grupo de Recursos
az group create --name $RESOURCE_GROUP --location $LOCATION

# 2. Crear Red y Subredes
az network vnet create \
    --name $VNET_NAME \
    --resource-group $RESOURCE_GROUP \
    --address-prefix 10.0.0.0/16 \
    --subnet-name $SUBNET_APP_NAME \
    --subnet-prefix 10.0.1.0/24

az network vnet subnet create \
    --name $SUBNET_GW_NAME \
    --resource-group $RESOURCE_GROUP \
    --vnet-name $VNET_NAME \
    --address-prefix 10.0.2.0/24

# 3. Crea IP del Gateway
az network public-ip create \
    --resource-group $RESOURCE_GROUP \
    --name $PUBLIC_IP_NAME \
    --sku Standard \
    --allocation-method Static

# 4. Crear la MV
az vm create \
  --resource-group $RESOURCE_GROUP \
  --name $VM_NAME \
  --image $VM_IMAGE \
  --size Standard_B1s \
  --vnet-name $VNET_NAME \
  --subnet $SUBNET_APP_NAME \
  --nsg $NSG_NAME \
  --admin-username "azureuser" \
  --generate-ssh-keys \
  --custom-data \
'#!/bin/bash
sudo apt-get update
sudo apt-get install -y apache2
echo "<html><h1>Hola desde mi VM en Azure!</h1></html>" | sudo tee /var/www/html/index.html'

# 5. Configuración del Gateway
VM_PRIVATE_IP=$(az vm show --resource-group $RESOURCE_GROUP --name $VM_NAME --show-details --query "privateIps" -o tsv | tr -d '\r\n')

az network application-gateway create \
    --name $GW_NAME \
    --resource-group $RESOURCE_GROUP \
    --location $LOCATION \
    --sku Standard_v2 \
    --public-ip-address $PUBLIC_IP_NAME \
    --vnet-name $VNET_NAME \
    --subnet $SUBNET_GW_NAME \
    --servers $VM_PRIVATE_IP \
    --http-settings-protocol Http \
    --http-settings-port 80 \
    --frontend-port 80 \
    --priority 100


# 6. Reglas de acceso al Firewall
az network nsg rule create \
    --resource-group $RESOURCE_GROUP \
    --nsg-name $NSG_NAME \
    --name PermitirHttpDesdeGateway \
    --protocol Tcp \
    --direction Inbound \
    --priority 200 \
    --source-address-prefixes "10.0.2.0/24" \
    --source-port-ranges '*' \
    --destination-address-prefixes '*' \
    --destination-port-ranges 80 \
    --access Allow

# 7. Verificación final
echo "¡Despliegue completado con éxito!"
GW_PUBLIC_IP=$(az network public-ip show --resource-group $RESOURCE_GROUP --name $PUBLIC_IP_NAME --query "ipAddress" -o tsv)
echo "http://$GW_PUBLIC_IP"