# ─────────────────────────────────────────────────────────────────
# FICHIER "backend.tf" — Configuration centrale de Terraform
#
# Ce fichier répond à 3 questions fondamentales :
#   1. Quelle version de Terraform utiliser ?
#   2. Quels providers (plugins) AWS utiliser ?
#   3. Où stocker le fichier d'état (tfstate) ?
# ─────────────────────────────────────────────────────────────────

# Bloc principal de configuration de Terraform lui-même
terraform {

  # Version minimale de Terraform requise pour exécuter ce code
  # "~> 1.13.0" signifie : accepte 1.13.0 et toutes les versions 1.13.x (patch)
  # mais PAS 1.14.0 — évite les incompatibilités dues aux nouvelles versions majeures
  # Si quelqu'un essaie avec Terraform 1.12 ou 2.0, Terraform refusera de s'exécuter
  required_version = "~> 1.13.0"

  # Déclare les providers (plugins) nécessaires pour ce projet
  # Un provider = un connecteur vers une plateforme cloud (AWS, Azure, GCP...)
  required_providers {

    # Provider AWS : le plugin officiel qui permet à Terraform de parler à l'API AWS
    aws = {
      # Source officielle du provider — "hashicorp/aws" = maintenu par HashiCorp (créateurs de Terraform)
      # Terraform le télécharge depuis registry.terraform.io lors du "terraform init"
      source = "hashicorp/aws"

      # Version du provider AWS à utiliser
      # "~> 5.49.0" = accepte 5.49.0 et les patches 5.49.x, mais PAS 5.50.0
      # Garantit la stabilité : les nouvelles versions majeures peuvent casser des ressources existantes
      version = "~> 5.49.0"
    }
  }

  # ─────────────────────────────────────────────────────────────────
  # BACKEND S3 — Stockage distant du fichier d'état Terraform (tfstate)
  #
  # Par défaut, Terraform stocke l'état dans un fichier local "terraform.tfstate"
  # Problème : si plusieurs personnes travaillent sur le projet, les états divergent
  # Solution : stocker l'état dans S3 (partagé et versionné) avec un lock pour éviter
  # que deux personnes modifient l'infra en même temps
  # ─────────────────────────────────────────────────────────────────
  backend "s3" {

    # Nom du bucket S3 où sera stocké le fichier tfstate
    # Ce bucket DOIT exister avant de faire "terraform init" — Terraform ne le crée pas lui-même
    bucket = "dev-edem-tf-bucket"

    # Région AWS où se trouve le bucket S3
    # Doit correspondre à la région réelle du bucket
    region = "us-east-1"

    # Chemin (clé) du fichier tfstate dans le bucket S3
    # ex: le fichier sera accessible à s3://dev-edem-tf-bucket/eks/terraform.tfstate
    # Utiliser des sous-dossiers permet de gérer plusieurs environnements dans le même bucket
    # ex: "dev/terraform.tfstate", "prod/terraform.tfstate", "eks/terraform.tfstate"
    key = "eks/terraform.tfstate"

    # Active le verrouillage du fichier d'état via un fichier .tflock dans S3
    # Quand quelqu'un fait "terraform apply", Terraform pose un verrou
    # Si une 2ème personne essaie en même temps → Terraform refuse et affiche une erreur
    # Évite la corruption du tfstate par des modifications simultanées
    # Note: avant Terraform 1.10, on utilisait DynamoDB pour le lock — use_lockfile est la nouvelle méthode native S3
    use_lockfile = true

    # Active le chiffrement côté serveur (SSE) du fichier tfstate dans S3
    # Le tfstate contient des informations sensibles (IDs de ressources, parfois des secrets)
    # true = AWS chiffre automatiquement le fichier au repos avec AES-256
    encrypt = true
  }
}

# ─────────────────────────────────────────────────────────────────
# PROVIDER AWS — Configuration de la connexion à AWS
#
# Le provider traduit les ressources Terraform en appels API AWS
# Il utilise les credentials AWS configurés localement (AWS CLI, variables d'environnement,
# rôle IAM de l'instance EC2, etc.)
# ─────────────────────────────────────────────────────────────────
provider "aws" {
  # Région AWS par défaut pour toutes les ressources créées par ce projet
  # La valeur vient d'une variable (définie dans variables.tf), ex: "us-east-1", "eu-west-1"
  # Toutes les ressources sans région explicite seront créées dans cette région
  region = var.aws-region
}
