# ═════════════════════════════════════════════════════════════════════════════
# FICHIER : main.tf — Point d'entrée et orchestrateur de l'infrastructure
# ═════════════════════════════════════════════════════════════════════════════
#
# C'est le fichier central du projet. Son rôle est d'appeler le MODULE "eks"
# situé dans le dossier "../modules" en lui passant toutes les valeurs
# nécessaires à la création de l'infrastructure.
#
# ARCHITECTURE DU PROJET :
#
#   eks/                       ← Dossier racine (tu es ici)
#   ├── main.tf                ← CE FICHIER : appelle le module avec les valeurs
#   ├── backend.tf             ← Configuration Terraform + stockage du tfstate
#   ├── variables.tf           ← Déclaration des variables attendues
#   └── dev.tfvars             ← Valeurs concrètes pour l'environnement dev
#
#   modules/                   ← Dossier du module réutilisable
#   ├── vpc.tf                 ← Crée le VPC, subnets, IGW, NAT, routes
#   ├── iam.tf                 ← Crée les rôles IAM pour EKS et les nodes
#   ├── eks.tf                 ← Crée le cluster EKS, node groups, add-ons
#   └── gather.tf              ← Lit les données existantes (OIDC, certificat)
#
# CONCEPT CLÉ — MODULE :
#   Un module Terraform = un dossier contenant des fichiers .tf réutilisables.
#   Comme une fonction en programmation : on lui passe des paramètres (inputs),
#   il crée des ressources et peut retourner des valeurs (outputs).
#
#   Avantage : le même module peut être appelé plusieurs fois avec des valeurs
#   différentes pour créer des environnements identiques (dev, staging, prod).
#
# CONVENTION DE NOMMAGE :
#   Toutes les ressources sont nommées selon le pattern :
#     "<env>-<org>-<nom>"
#   ex: "dev-ap-medium-vpc", "dev-ap-medium-eks-cluster", "dev-ap-medium-igw"
#   → Permet d'identifier immédiatement à quel environnement et projet appartient
#     une ressource dans la console AWS
#
# SECTIONS DE CE FICHIER :
#   1. locals       → Variables locales (env, org) pour construire les noms
#   2. module "eks" → Appel du module avec tous ses paramètres groupés par thème :
#        - Réseau VPC (CIDR, subnets publics/privés, IGW, NAT, routes)
#        - IAM       (activation des rôles cluster et node group)
#        - EKS       (cluster, node groups on-demand et spot, add-ons)
#
# ═════════════════════════════════════════════════════════════════════════════

locals {
  org = "ap-medium"
  env = var.env
}

module "eks" {
  source = "../modules"

  env                   = var.env
  cluster-name          = "${local.env}-${local.org}-${var.cluster-name}"
  cidr-block            = var.vpc-cidr-block
  vpc-name              = "${local.env}-${local.org}-${var.vpc-name}"
  igw-name              = "${local.env}-${local.org}-${var.igw-name}"
  pub-subnet-count      = var.pub-subnet-count
  pub-cidr-block        = var.pub-cidr-block
  pub-availability-zone = var.pub-availability-zone
  pub-sub-name          = "${local.env}-${local.org}-${var.pub-sub-name}"
  pri-subnet-count      = var.pri-subnet-count
  pri-cidr-block        = var.pri-cidr-block
  pri-availability-zone = var.pri-availability-zone
  pri-sub-name          = "${local.env}-${local.org}-${var.pri-sub-name}"
  public-rt-name        = "${local.env}-${local.org}-${var.public-rt-name}"
  private-rt-name       = "${local.env}-${local.org}-${var.private-rt-name}"
  eip-name              = "${local.env}-${local.org}-${var.eip-name}"
  ngw-name              = "${local.env}-${local.org}-${var.ngw-name}"
  eks-sg                = var.eks-sg

  is_eks_role_enabled           = true
  is_eks_nodegroup_role_enabled = true
  ondemand_instance_types       = var.ondemand_instance_types
  spot_instance_types           = var.spot_instance_types
  desired_capacity_on_demand    = var.desired_capacity_on_demand
  min_capacity_on_demand        = var.min_capacity_on_demand
  max_capacity_on_demand        = var.max_capacity_on_demand
  desired_capacity_spot         = var.desired_capacity_spot
  min_capacity_spot             = var.min_capacity_spot
  max_capacity_spot             = var.max_capacity_spot
  is-eks-cluster-enabled        = var.is-eks-cluster-enabled
  cluster-version               = var.cluster-version
  endpoint-private-access       = var.endpoint-private-access
  endpoint-public-access        = var.endpoint-public-access

  addons = var.addons
}