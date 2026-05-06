# ─────────────────────────────────────────────────────────────────
# CLUSTER EKS (Elastic Kubernetes Service)
# C'est le "control plane" de Kubernetes : le cerveau qui orchestre tous les pods/nodes
# AWS gère entièrement le control plane (API server, etcd, scheduler...) — on paie juste les nodes
# ─────────────────────────────────────────────────────────────────

resource "aws_eks_cluster" "eks" {

  # Création conditionnelle : si la variable est true → 1 cluster créé, sinon 0
  # Permet d'activer/désactiver la création du cluster via une variable
  count = var.is-eks-cluster-enabled == true ? 1 : 0

  # Nom du cluster EKS — visible dans la console AWS et utilisé par kubectl
  name = var.cluster-name

  # ARN du rôle IAM que le control plane EKS va endosser pour gérer les ressources AWS
  # [count.index] car le rôle a aussi été créé avec count (liste d'un seul élément)
  role_arn = aws_iam_role.eks-cluster-role[count.index].arn

  # Version de Kubernetes à utiliser, ex: "1.29" — à mettre à jour régulièrement
  version = var.cluster-version

  # Configuration réseau du cluster
  vpc_config {
    # Les sous-réseaux PRIVÉS où le control plane placera les interfaces réseau (ENI)
    # On passe les 3 subnets privés (un par AZ) pour la haute disponibilité
    subnet_ids = [
      aws_subnet.private-subnet[0].id, # subnet privé AZ-1
      aws_subnet.private-subnet[1].id, # subnet privé AZ-2
      aws_subnet.private-subnet[2].id, # subnet privé AZ-3
    ]

    # true = l'API Kubernetes est accessible depuis l'intérieur du VPC (réseau privé)
    # Permet aux nodes et aux outils internes (ex: Jenkins) de communiquer avec l'API server
    endpoint_private_access = var.endpoint-private-access

    # true = l'API Kubernetes est accessible depuis Internet (via kubectl depuis ton poste)
    # false en prod recommandé — ici configurable via variable
    endpoint_public_access = var.endpoint-public-access

    # Security group attaché au control plane EKS — contrôle qui peut joindre l'API server (port 443)
    security_group_ids = [aws_security_group.eks-cluster-sg.id]
  }

  # Configuration du mode d'authentification au cluster
  access_config {
    # "CONFIG_MAP" = méthode classique via le ConfigMap "aws-auth" dans Kubernetes
    # C'est ce ConfigMap qui mappe les rôles IAM aux utilisateurs/groupes Kubernetes
    authentication_mode = "CONFIG_MAP"

    # true = la personne/le rôle qui crée le cluster obtient automatiquement les droits admin
    # Évite d'être bloqué hors du cluster juste après sa création
    bootstrap_cluster_creator_admin_permissions = true
  }

  tags = {
    Name = var.cluster-name
    Env  = var.env
  }
}

# ─────────────────────────────────────────────────────────────────
# OIDC PROVIDER — Fournisseur d'identité pour le cluster
# Permet à AWS IAM de faire confiance aux tokens JWT émis par le cluster EKS
# Prérequis pour que les pods puissent obtenir des credentials AWS (mécanisme IRSA)
# ─────────────────────────────────────────────────────────────────

resource "aws_iam_openid_connect_provider" "eks-oidc" {
  # Liste des audiences autorisées à recevoir les tokens OIDC
  # "sts.amazonaws.com" = AWS Security Token Service — le service qui échange les tokens contre des credentials
  client_id_list = ["sts.amazonaws.com"]

  # Empreinte SHA1 du certificat TLS de l'émetteur OIDC
  # AWS l'utilise pour vérifier l'authenticité des tokens JWT
  # Récupérée depuis le data source "tls_certificate" défini dans gather.tf
  thumbprint_list = [data.tls_certificate.eks-certificate.certificates[0].sha1_fingerprint]

  # URL de l'émetteur OIDC du cluster, ex: "https://oidc.eks.eu-west-1.amazonaws.com/id/XXXX"
  # Récupérée depuis le même data source
  url = data.tls_certificate.eks-certificate.url
}

# ─────────────────────────────────────────────────────────────────
# ADD-ONS EKS — Extensions officielles gérées par AWS pour le cluster
# Les add-ons sont des composants système essentiels (réseau, DNS, stockage...)
# AWS les maintient et les met à jour automatiquement
# ─────────────────────────────────────────────────────────────────

resource "aws_eks_addon" "eks-addons" {
  # "for_each" itère sur la liste var.addons pour créer un add-on par entrée
  # { for idx, addon in var.addons : idx => addon } convertit la liste en map (requis par for_each)
  # Exemples d'add-ons courants : "vpc-cni", "coredns", "kube-proxy", "aws-ebs-csi-driver"
  for_each = { for idx, addon in var.addons : idx => addon }

  # Nom du cluster auquel rattacher l'add-on
  cluster_name = aws_eks_cluster.eks[0].name

  # Nom de l'add-on pour l'itération courante (ex: "vpc-cni")
  addon_name = each.value.name

  # Version spécifique de l'add-on (ex: "v1.16.0-eksbuild.1")
  addon_version = each.value.version

  # Les add-ons ne peuvent être installés qu'APRÈS que les nodes existent
  # (certains add-ons ont besoin de nodes pour s'exécuter, ex: CoreDNS)
  depends_on = [
    aws_eks_node_group.ondemand-node, # attend que les nodes on-demand soient prêts
    aws_eks_node_group.spot-node,     # attend que les nodes spot soient prêts
  ]
}

# ─────────────────────────────────────────────────────────────────
# NODE GROUP "ON-DEMAND" — Instances EC2 à prix fixe
# Les nodes on-demand sont stables et ne peuvent pas être interrompus par AWS
# Utilisés pour les workloads critiques qui ne supportent pas d'interruption
# ─────────────────────────────────────────────────────────────────

resource "aws_eks_node_group" "ondemand-node" {
  # Cluster auquel appartient ce groupe de nodes
  cluster_name = aws_eks_cluster.eks[0].name

  # Nom du node group visible dans la console AWS
  node_group_name = "${var.cluster-name}-on-demand-nodes"

  # Rôle IAM que les nodes EC2 vont endosser (droits ECR, CNI, EBS... définis dans iam.tf)
  node_role_arn = aws_iam_role.eks-nodegroup-role[0].arn

  # Configuration de l'autoscaling du groupe de nodes
  scaling_config {
    # Nombre de nodes voulu en fonctionnement normal
    desired_size = var.desired_capacity_on_demand

    # Nombre minimum de nodes — EKS ne descendra jamais en dessous
    min_size = var.min_capacity_on_demand

    # Nombre maximum de nodes — EKS ne montera jamais au-dessus
    max_size = var.max_capacity_on_demand
  }

  # Les nodes sont lancés dans les sous-réseaux PRIVÉS (pas d'IP publique directe)
  # Répartis sur 3 AZs pour la résilience
  subnet_ids = [
    aws_subnet.private-subnet[0].id,
    aws_subnet.private-subnet[1].id,
    aws_subnet.private-subnet[2].id,
  ]

  # Types d'instances EC2 à utiliser, ex: ["t3.medium", "t3.large"]
  # On peut en lister plusieurs pour qu'EKS choisisse selon la disponibilité
  instance_types = var.ondemand_instance_types

  # "ON_DEMAND" = instances à prix fixe, non interruptibles — plus cher mais plus stable
  capacity_type = "ON_DEMAND"

  # Labels Kubernetes appliqués à tous les nodes de ce groupe
  # Permet de cibler ces nodes avec nodeSelector ou nodeAffinity dans les manifests K8s
  labels = {
    type = "ondemand" # ex: un pod peut forcer son exécution sur des nodes "ondemand"
  }

  # Configuration des mises à jour du node group
  update_config {
    # Nombre maximum de nodes qui peuvent être indisponibles SIMULTANÉMENT lors d'une mise à jour
    # 1 = mise à jour "rolling" prudente — un node à la fois
    max_unavailable = 1
  }

  # Tag appliqué uniquement à la ressource AWS EKS Node Group
  tags = {
    "Name" = "${var.cluster-name}-ondemand-nodes"
  }

  # Tags appliqués à TOUTES les ressources créées par ce node group (instances EC2, volumes EBS, etc.)
  tags_all = {
    # Tag requis par Kubernetes pour identifier les ressources appartenant au cluster
    "kubernetes.io/cluster/${var.cluster-name}" = "owned"
    "Name"                                       = "${var.cluster-name}-ondemand-nodes"
  }

  # Le cluster EKS doit exister avant de pouvoir y ajouter des nodes
  depends_on = [aws_eks_cluster.eks]
}

# ─────────────────────────────────────────────────────────────────
# NODE GROUP "SPOT" — Instances EC2 à prix réduit (jusqu'à -90%)
# Les instances Spot utilisent la capacité inutilisée d'AWS — moins chères mais interruptibles
# AWS peut récupérer ces instances avec un préavis de 2 minutes
# Utilisées pour les workloads tolérants aux interruptions (batch, CI/CD, workers...)
# ─────────────────────────────────────────────────────────────────

resource "aws_eks_node_group" "spot-node" {
  cluster_name    = aws_eks_cluster.eks[0].name
  node_group_name = "${var.cluster-name}-spot-nodes"

  node_role_arn = aws_iam_role.eks-nodegroup-role[0].arn

  scaling_config {
    desired_size = var.desired_capacity_spot # nombre de nodes spot souhaités
    min_size     = var.min_capacity_spot     # minimum de nodes spot
    max_size     = var.max_capacity_spot     # maximum de nodes spot
  }

  # Même répartition sur les 3 AZs privées — plus d'AZs = plus de chances de trouver de la capacité spot
  subnet_ids = [
    aws_subnet.private-subnet[0].id,
    aws_subnet.private-subnet[1].id,
    aws_subnet.private-subnet[2].id,
  ]

  # Types d'instances spot — on en liste plusieurs pour maximiser les chances de disponibilité
  # Si un type est indisponible en spot, AWS essaie le suivant
  instance_types = var.spot_instance_types

  # "SPOT" = instances interruptibles à prix réduit
  capacity_type = "SPOT"

  update_config {
    # Même que pour on-demand : mise à jour progressive, 1 node à la fois
    max_unavailable = 1
  }

  tags = {
    "Name" = "${var.cluster-name}-spot-nodes"
  }

  tags_all = {
    "kubernetes.io/cluster/${var.cluster-name}" = "owned"
    # Note : ce tag pointe vers "ondemand-nodes" — c'est probablement une erreur de copier-coller
    "Name" = "${var.cluster-name}-ondemand-nodes"
  }

  # Labels Kubernetes pour identifier ces nodes comme "spot" dans les workloads
  labels = {
    type      = "spot"      # type de capacité
    lifecycle = "spot"      # utile pour les règles d'affinité et les node selectors
  }

  # Taille du disque racine des instances EC2 en Go
  # 50 Go pour stocker les images Docker et les données temporaires des pods
  disk_size = 50

  depends_on = [aws_eks_cluster.eks]
}
