# ═════════════════════════════════════════════════════════════════════════════
# FICHIER : dev.tfvars — Valeurs des variables pour l'environnement DEV
# ═════════════════════════════════════════════════════════════════════════════
#
# Un fichier ".tfvars" contient les VALEURS concrètes des variables déclarées
# dans variables.tf. Il ne contient pas de logique, seulement des assignations.
#
# Utilisation :
#   terraform apply -var-file="dev.tfvars"
#
# En pratique, on crée un fichier par environnement :
#   dev.tfvars   → environnement de développement  (ce fichier)
#   stg.tfvars   → environnement de staging
#   prod.tfvars  → environnement de production
#
# Le même code Terraform est réutilisé pour tous les environnements —
# seules les valeurs changent (taille des instances, nombre de nodes, CIDR...).
#
# ─────────────────────────────────────────────────────────────────────────────
# SECTION 1 — GÉNÉRAL
# ─────────────────────────────────────────────────────────────────────────────
#
#   env        = "dev"         → Étiquette l'environnement (utilisé dans les tags AWS)
#   aws-region = "us-east-1"  → Région AWS où toute l'infrastructure sera déployée
#
# ─────────────────────────────────────────────────────────────────────────────
# SECTION 2 — RÉSEAU VPC (Virtual Private Cloud)
# ─────────────────────────────────────────────────────────────────────────────
#
#   vpc-cidr-block = "10.16.0.0/16"
#     → Plage d'adresses IP du VPC entier : de 10.16.0.0 à 10.16.255.255
#       soit 65 536 adresses IP disponibles (/16 = 16 bits fixes, 16 bits libres)
#
#   Sous-réseaux PUBLICS (accessibles depuis Internet) :
#     pub-subnet-count      = 3       → 3 subnets publics (un par zone de disponibilité)
#     pub-cidr-block        = [...]   → Chaque subnet a une plage de 4096 IPs (/20)
#       "10.16.0.0/20"   → AZ us-east-1a  (IPs : 10.16.0.0  → 10.16.15.255)
#       "10.16.16.0/20"  → AZ us-east-1b  (IPs : 10.16.16.0 → 10.16.31.255)
#       "10.16.32.0/20"  → AZ us-east-1c  (IPs : 10.16.32.0 → 10.16.47.255)
#     pub-availability-zone = [...]   → Répartition sur 3 AZs pour la haute disponibilité
#
#   Sous-réseaux PRIVÉS (non accessibles depuis Internet, trafic sortant via NAT) :
#     pri-subnet-count      = 3       → 3 subnets privés (un par AZ)
#     pri-cidr-block        = [...]   → Même taille /20, mais dans une plage différente
#       "10.16.128.0/20"  → AZ us-east-1a  (IPs : 10.16.128.0 → 10.16.143.255)
#       "10.16.144.0/20"  → AZ us-east-1b  (IPs : 10.16.144.0 → 10.16.159.255)
#       "10.16.160.0/20"  → AZ us-east-1c  (IPs : 10.16.160.0 → 10.16.175.255)
#
#   Noms des ressources réseau :
#     igw-name        = "igw"                  → Internet Gateway
#     pub-sub-name    = "subnet-public"        → Préfixe des subnets publics
#     pri-sub-name    = "subnet-private"       → Préfixe des subnets privés
#     public-rt-name  = "public-route-table"   → Table de routage publique
#     private-rt-name = "private-route-table"  → Table de routage privée
#     eip-name        = "elasticip-ngw"        → IP fixe du NAT Gateway
#     ngw-name        = "ngw"                  → NAT Gateway
#     eks-sg          = "eks-sg"               → Security Group du cluster EKS
#
# ─────────────────────────────────────────────────────────────────────────────
# SECTION 3 — CLUSTER EKS (Elastic Kubernetes Service)
# ─────────────────────────────────────────────────────────────────────────────
#
#   is-eks-cluster-enabled  = true      → Active la création du cluster (feature flag)
#   cluster-name            = "eks-cluster"
#   cluster-version         = "1.33"    → Version de Kubernetes à déployer
#   endpoint-private-access = true      → L'API K8s est accessible depuis le VPC (interne)
#   endpoint-public-access  = false     → L'API K8s N'EST PAS exposée sur Internet (sécurisé)
#
#   Nodes ON-DEMAND (prix fixe, non interruptibles) :
#     ondemand_instance_types    = ["t3a.medium"]  → Type d'instance EC2 (2 vCPU, 4 Go RAM)
#     desired_capacity_on_demand = "1"  → 1 node au démarrage
#     min_capacity_on_demand     = "1"  → jamais moins de 1 node
#     max_capacity_on_demand     = "5"  → jamais plus de 5 nodes (autoscaling)
#
#   Nodes SPOT (prix réduit jusqu'à -90%, interruptibles par AWS) :
#     spot_instance_types = [...]  → Liste variée de types pour maximiser la disponibilité spot
#       c5a.large, c5a.xlarge     → instances optimisées calcul (AMD)
#       m5a.large, m5a.xlarge     → instances usage général (AMD)
#       c5.large, m5.large        → instances Intel équivalentes (fallback)
#       t3a.large, t3a.xlarge, t3a.medium → instances polyvalentes burstables (AMD)
#     desired_capacity_spot = "1"   → 1 node spot au démarrage
#     min_capacity_spot     = "1"   → minimum 1 node spot
#     max_capacity_spot     = "10"  → jusqu'à 10 nodes spot (autoscaling agressif)
#
# ─────────────────────────────────────────────────────────────────────────────
# SECTION 4 — ADD-ONS EKS (extensions système du cluster)
# ─────────────────────────────────────────────────────────────────────────────
#
#   vpc-cni (v1.20.0)
#     → Plugin réseau AWS : assigne des IPs VPC directement aux pods
#       Chaque pod a une IP réelle dans le VPC (pas de NAT entre pods et VPC)
#
#   coredns (v1.12.2)
#     → Serveur DNS interne de Kubernetes
#       Permet aux pods de se trouver par nom (ex: "mon-service.default.svc.cluster.local")
#
#   kube-proxy (v1.33.0)
#     → Gère les règles réseau (iptables/ipvs) sur chaque node
#       Permet au trafic d'atteindre les bons pods derrière un Service Kubernetes
#
#   aws-ebs-csi-driver (v1.46.0)
#     → Driver de stockage : permet à Kubernetes de créer/attacher des volumes EBS
#       Nécessaire pour les PersistentVolumeClaims (stockage persistant des pods)
#
# ═════════════════════════════════════════════════════════════════════════════

env                   = "dev"
aws-region            = "us-east-1"
vpc-cidr-block        = "10.16.0.0/16"
vpc-name              = "vpc"
igw-name              = "igw"
pub-subnet-count      = 3
pub-cidr-block        = ["10.16.0.0/20", "10.16.16.0/20", "10.16.32.0/20"]
pub-availability-zone = ["us-east-1a", "us-east-1b", "us-east-1c"]
pub-sub-name          = "subnet-public"
pri-subnet-count      = 3
pri-cidr-block        = ["10.16.128.0/20", "10.16.144.0/20", "10.16.160.0/20"]
pri-availability-zone = ["us-east-1a", "us-east-1b", "us-east-1c"]
pri-sub-name          = "subnet-private"
public-rt-name        = "public-route-table"
private-rt-name       = "private-route-table"
eip-name              = "elasticip-ngw"
ngw-name              = "ngw"
eks-sg                = "eks-sg"

# EKS
is-eks-cluster-enabled     = true
cluster-version            = "1.33"
cluster-name               = "eks-cluster"
endpoint-private-access    = true
endpoint-public-access     = false
ondemand_instance_types    = ["t3a.medium"]
spot_instance_types        = ["c5a.large", "c5a.xlarge", "m5a.large", "m5a.xlarge", "c5.large", "m5.large", "t3a.large", "t3a.xlarge", "t3a.medium"]
desired_capacity_on_demand = "1"
min_capacity_on_demand     = "1"
max_capacity_on_demand     = "5"
desired_capacity_spot      = "1"
min_capacity_spot          = "1"
max_capacity_spot          = "10"
addons = [
  {
    name    = "vpc-cni",
    version = "v1.20.0-eksbuild.1"
  },
  {
    name    = "coredns"
    version = "v1.12.2-eksbuild.4"
  },
  {
    name    = "kube-proxy"
    version = "v1.33.0-eksbuild.2"
  },
  {
    name    = "aws-ebs-csi-driver"
    version = "v1.46.0-eksbuild.1"
  }
  # Add more addons as needed
]