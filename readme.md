# Azure Secure Hub-and-Spoke Infrastructure

## Descripción
Este proyecto despliega una topología de red Hub-and-Spoke segura en Microsoft Azure. 
Está diseñado como parte de mi preparación para la certificación **AZ-104**.

## Objetivos Técnicos
* Implementar una **VNet Hub** centralizada con **Azure Firewall**.
* Configurar **VNet Peering** entre redes aisladas (Spokes).
* Controlar el flujo de tráfico mediante **User Defined Routes (UDR)**.
* Asegurar el acceso mediante **Azure Bastion**.

## Arquitectura
```mermaid 
graph TD
    subgraph Azure_Cloud
        subgraph VNet_Hub
            FW[Azure Firewall]
            Bastion[Azure Bastion]
        end
        subgraph VNet_Spoke_A
            VM1[Workload VM]
        end
        subgraph VNet_Spoke_B
            VM2[Database VM]
        end
        VNet_Spoke_A <-->|Peering| VNet_Hub
        VNet_Spoke_B <-->|Peering| VNet_Hub
        VM1 -.->|UDR: Next Hop FW| FW
        VM2 -.->|UDR: Next Hop FW| FW
    end
``` 
![Arquitectura Hub-and-Spoke](./img2/diagrama-arquitectura.png)