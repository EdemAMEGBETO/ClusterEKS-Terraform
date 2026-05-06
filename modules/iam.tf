# Bloc "locals" : variable locale pour éviter de répéter var.cluster-name partout dans le fichier
locals {
  # Récupère le nom du cluster depuis les variables — accessible via local.cluster_name
  cluster_name = var.cluster-name
}

# Génère un nombre entier aléatoire entre 1000 et 9999
# Utilisé pour rendre les noms de rôles IAM uniques et éviter les conflits si on recrée l'infra
resource "random_integer" "random_suffix" {
  min = 1000 # valeur minimale du nombre généré
  max = 9999 # valeur maximale du nombre généré
}

# ─────────────────────────────────────────────────────────────────
# RÔLE IAM POUR LE CLUSTER EKS
# Un rôle IAM = une identité AWS qu'un service peut "endosser" pour obtenir des permissions
# ─────────────────────────────────────────────────────────────────

resource "aws_iam_role" "eks-cluster-role" {
  # Création conditionnelle : si var.is_eks_role_enabled est true → crée 1 rôle, sinon 0 (pas de création)
  # C'est le pattern "feature flag" en Terraform
  count = var.is_eks_role_enabled ? 1 : 0

  # Nom unique du rôle : ex "my-cluster-role-4782" — le suffixe aléatoire évite les doublons
  name = "${local.cluster_name}-role-${random_integer.random_suffix.result}"

  # "Assume Role Policy" = qui a le droit d'utiliser ce rôle ?
  # jsonencode() convertit un objet Terraform en JSON valide pour AWS
  assume_role_policy = jsonencode({
    Version = "2012-10-17" # version standard du langage de politique IAM d'AWS (ne pas changer)
    Statement = [{
      Effect = "Allow" # autorise (vs "Deny" qui interdirait)
      Principal = {
        Service = "eks.amazonaws.com" # seul le service EKS peut endosser ce rôle
      }
      Action = "sts:AssumeRole" # l'action autorisée : "prendre l'identité de ce rôle"
    }]
  })
}

# Attache la politique AWS gérée "AmazonEKSClusterPolicy" au rôle du cluster
# Cette politique donne à EKS les droits nécessaires pour gérer le cluster (créer/modifier des ressources AWS)
resource "aws_iam_role_policy_attachment" "AmazonEKSClusterPolicy" {
  # Même condition que le rôle : ne s'exécute que si le rôle a été créé
  count = var.is_eks_role_enabled ? 1 : 0

  # ARN de la politique AWS managée — "aws:policy/" indique que c'est une politique fournie par AWS
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"

  # Nom du rôle auquel attacher cette politique — [count.index] car c'est une liste (créée avec count)
  role = aws_iam_role.eks-cluster-role[count.index].name
}

# ─────────────────────────────────────────────────────────────────
# RÔLE IAM POUR LES NODES DU CLUSTER (Node Group)
# Les nodes sont des instances EC2 — elles ont besoin d'un rôle pour s'identifier auprès d'EKS
# ─────────────────────────────────────────────────────────────────

resource "aws_iam_role" "eks-nodegroup-role" {
  # Création conditionnelle selon la variable is_eks_nodegroup_role_enabled
  count = var.is_eks_nodegroup_role_enabled ? 1 : 0

  # Nom unique du rôle des nodes : ex "my-cluster-nodegroup-role-4782"
  name = "${local.cluster_name}-nodegroup-role-${random_integer.random_suffix.result}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole" # les instances EC2 pourront endosser ce rôle
      Effect = "Allow"
      Principal = {
        Service = "ec2.amazonaws.com" # seul le service EC2 (les nodes) peut utiliser ce rôle
      }
    }]
  })
}

# Politique 1/4 : droits de base pour qu'un node fonctionne dans EKS
# (s'enregistrer auprès du cluster, décrire les ressources AWS, etc.)
resource "aws_iam_role_policy_attachment" "eks-AmazonWorkerNodePolicy" {
  count      = var.is_eks_nodegroup_role_enabled ? 1 : 0
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
  role       = aws_iam_role.eks-nodegroup-role[count.index].name
}

# Politique 2/4 : droits pour le plugin réseau CNI (Container Network Interface)
# Le CNI gère les adresses IP des pods — il a besoin de modifier les interfaces réseau des instances EC2
resource "aws_iam_role_policy_attachment" "eks-AmazonEKS_CNI_Policy" {
  count      = var.is_eks_nodegroup_role_enabled ? 1 : 0
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
  role       = aws_iam_role.eks-nodegroup-role[count.index].name
}

# Politique 3/4 : accès en LECTURE SEULE à ECR (Elastic Container Registry)
# Permet aux nodes de télécharger (pull) les images Docker stockées dans ECR
resource "aws_iam_role_policy_attachment" "eks-AmazonEC2ContainerRegistryReadOnly" {
  count      = var.is_eks_nodegroup_role_enabled ? 1 : 0
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
  role       = aws_iam_role.eks-nodegroup-role[count.index].name
}

# Politique 4/4 : droits pour le driver CSI EBS (Elastic Block Store)
# Permet à Kubernetes de créer/attacher/détacher des volumes EBS comme stockage persistant pour les pods
resource "aws_iam_role_policy_attachment" "eks-AmazonEBSCSIDriverPolicy" {
  count      = var.is_eks_nodegroup_role_enabled ? 1 : 0
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy"
  role       = aws_iam_role.eks-nodegroup-role[count.index].name
}

# ─────────────────────────────────────────────────────────────────
# OIDC (OpenID Connect) — Identité pour les pods Kubernetes
# OIDC permet à des pods spécifiques d'obtenir des droits AWS SANS passer par les credentials des nodes
# C'est le mécanisme "IRSA" (IAM Roles for Service Accounts)
# ─────────────────────────────────────────────────────────────────

# Rôle IAM associé à l'OIDC provider du cluster EKS
# La politique d'assumption est définie dans un "data source" (fichier séparé, ex: data.tf)
resource "aws_iam_role" "eks_oidc" {
  # Référence la politique définie dans data.aws_iam_policy_document.eks_oidc_assume_role_policy
  # Cette politique précise QUEL service account Kubernetes peut endosser ce rôle
  assume_role_policy = data.aws_iam_policy_document.eks_oidc_assume_role_policy.json

  # Nom fixe du rôle OIDC
  name = "eks-oidc"
}

# Politique IAM personnalisée attachée au rôle OIDC
# Définit CE QUE le pod pourra faire une fois qu'il a endossé le rôle
resource "aws_iam_policy" "eks-oidc-policy" {
  # Nom de la politique visible dans la console IAM
  name = "test-policy"

  # Contenu de la politique en JSON
  policy = jsonencode({
    Statement = [{
      Action = [
        "s3:ListAllMyBuckets", # lister tous les buckets S3 du compte
        "s3:GetBucketLocation", # obtenir la région d'un bucket S3
        "*"                     # ATTENTION : "*" autorise TOUTES les actions AWS — à ne jamais faire en production !
      ]
      Effect   = "Allow"  # toutes ces actions sont autorisées
      Resource = "*"      # sur TOUTES les ressources AWS — très permissif, à restreindre en prod
    }]
    Version = "2012-10-17"
  })
}

# Attache la politique personnalisée au rôle OIDC
# Le pod qui endosse ce rôle aura donc les droits S3 définis ci-dessus
resource "aws_iam_role_policy_attachment" "eks-oidc-policy-attach" {
  # Référence le rôle OIDC créé juste au-dessus
  role = aws_iam_role.eks_oidc.name

  # ARN de la politique personnalisée (pas une politique AWS managée, mais la nôtre)
  policy_arn = aws_iam_policy.eks-oidc-policy.arn
}
