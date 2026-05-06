# ═════════════════════════════════════════════════════════════════════════════
# FICHIER : variables.tf — Déclaration de toutes les variables du projet
# ═════════════════════════════════════════════════════════════════════════════
#
# Ce fichier déclare les "entrées" attendues par le projet, comme la signature
# d'une fonction en programmation. Il ne contient PAS les valeurs — celles-ci
# sont définies dans dev.tfvars (ou prod.tfvars, etc.).
#
# RELATION ENTRE LES FICHIERS :
#
#   variables.tf   →  déclare  "je m'appelle aws-region, je suis de type string"
#   dev.tfvars     →  valorise "aws-region = us-east-1"
#   main.tf        →  utilise  "var.aws-region"
#
# ANATOMIE D'UNE VARIABLE TERRAFORM :
#
#   variable "nom-de-la-variable" {
#     type        = string          ← type attendu (optionnel mais recommandé)
#     default     = "une-valeur"    ← valeur utilisée si aucune valeur fournie (optionnel)
#     description = "À quoi ça sert" ← documentation (optionnel mais bonne pratique)
#   }
#
#   → Si une variable n'a ni "default" ni valeur dans le .tfvars,
#     Terraform demandera la valeur interactivement au moment du "apply"
#
# TYPES TERRAFORM UTILISÉS DANS CE FICHIER :
#
#   string          → texte simple           ex: "us-east-1", "dev", "eks-cluster"
#   number          → nombre entier/décimal  ex: 3, 50
#   bool            → booléen               ex: true, false
#   list(string)    → liste de textes        ex: ["10.0.0.0/24", "10.0.1.0/24"]
#   list(object({…})) → liste d'objets structurés  ex: les add-ons EKS
#
#   Variables sans type déclaré (ex: variable "env" {}) sont implicitement
#   de type "any" — Terraform infère le type depuis la valeur fournie
#
# ─────────────────────────────────────────────────────────────────────────────
# SECTION 1 — GÉNÉRAL
# ─────────────────────────────────────────────────────────────────────────────
#
#   aws-region    → Région AWS cible (ex: "us-east-1")
#   env           → Nom de l'environnement, utilisé dans les tags et les noms (ex: "dev")
#   cluster-name  → Nom de base du cluster EKS (sera préfixé dans main.tf)
#
# ─────────────────────────────────────────────────────────────────────────────
# SECTION 2 — RÉSEAU VPC
# ─────────────────────────────────────────────────────────────────────────────
#
#   vpc-cidr-block         → Plage IP du VPC entier         (ex: "10.16.0.0/16")
#   vpc-name               → Nom du VPC                      (ex: "vpc")
#   igw-name               → Nom de l'Internet Gateway       (ex: "igw")
#
#   Subnets PUBLICS :
#     pub-subnet-count      → Nombre de subnets publics à créer  (ex: 3)
#     pub-cidr-block        → list(string) : plage IP de chaque subnet public
#     pub-availability-zone → list(string) : AZ de chaque subnet public
#     pub-sub-name          → Préfixe du nom des subnets publics
#
#   Subnets PRIVÉS :
#     pri-subnet-count      → Nombre de subnets privés à créer   (ex: 3)
#     pri-cidr-block        → list(string) : plage IP de chaque subnet privé
#     pri-availability-zone → list(string) : AZ de chaque subnet privé
#     pri-sub-name          → Préfixe du nom des subnets privés
#
#   Tables de routage et autres ressources réseau :
#     public-rt-name        → Nom de la route table publique
#     private-rt-name       → Nom de la route table privée
#     eip-name              → Nom de l'Elastic IP du NAT Gateway
#     ngw-name              → Nom du NAT Gateway
#     eks-sg                → Nom du Security Group du cluster EKS
#
# ─────────────────────────────────────────────────────────────────────────────
# SECTION 3 — CLUSTER EKS
# ─────────────────────────────────────────────────────────────────────────────
#
#   is-eks-cluster-enabled  → Booléen : active/désactive la création du cluster
#   cluster-version         → Version Kubernetes          (ex: "1.33")
#   endpoint-private-access → Booléen : API accessible depuis le VPC
#   endpoint-public-access  → Booléen : API accessible depuis Internet
#
#   Nodes ON-DEMAND (prix fixe, non interruptibles) :
#     ondemand_instance_types    → list(string) : types EC2, défaut: ["t3a.medium"]
#                                   ↑ Seule variable avec "default" dans ce fichier
#     desired_capacity_on_demand → Nombre cible de nodes on-demand
#     min_capacity_on_demand     → Minimum de nodes on-demand (autoscaling)
#     max_capacity_on_demand     → Maximum de nodes on-demand (autoscaling)
#
#   Nodes SPOT (prix réduit, interruptibles par AWS) :
#     spot_instance_types        → list(string) : types EC2 éligibles spot
#     desired_capacity_spot      → Nombre cible de nodes spot
#     min_capacity_spot          → Minimum de nodes spot
#     max_capacity_spot          → Maximum de nodes spot
#
#   Add-ons EKS :
#     addons → list(object({ name=string, version=string }))
#              Liste typée et structurée : chaque add-on doit avoir un "name"
#              et une "version" — Terraform validera la structure avant l'apply
#              ex: [{ name="vpc-cni", version="v1.20.0-eksbuild.1" }, ...]
#
# ═════════════════════════════════════════════════════════════════════════════

variable "aws-region" {}
variable "env" {}
variable "cluster-name" {}
variable "vpc-cidr-block" {}
variable "vpc-name" {}
variable "igw-name" {}
variable "pub-subnet-count" {}
variable "pub-cidr-block" {
  type = list(string)
}
variable "pub-availability-zone" {
  type = list(string)
}
variable "pub-sub-name" {}
variable "pri-subnet-count" {}
variable "pri-cidr-block" {
  type = list(string)
}
variable "pri-availability-zone" {
  type = list(string)
}
variable "pri-sub-name" {}
variable "public-rt-name" {}
variable "private-rt-name" {}
variable "eip-name" {}
variable "ngw-name" {}
variable "eks-sg" {}


# EKS
variable "is-eks-cluster-enabled" {}
variable "cluster-version" {}
variable "endpoint-private-access" {}
variable "endpoint-public-access" {}
variable "ondemand_instance_types" {
  default = ["t3a.medium"]
}

variable "spot_instance_types" {}
variable "desired_capacity_on_demand" {}
variable "min_capacity_on_demand" {}
variable "max_capacity_on_demand" {}
variable "desired_capacity_spot" {}
variable "min_capacity_spot" {}
variable "max_capacity_spot" {}
variable "addons" {
  type = list(object({
    name    = string
    version = string
  }))
}