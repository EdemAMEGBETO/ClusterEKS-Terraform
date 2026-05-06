# ─────────────────────────────────────────────────────────────────
# FICHIER "gather.tf" — Collecte de données externes (data sources)
#
# En Terraform, un bloc "data" ne CRÉE pas de ressource.
# Il lit des informations qui EXISTENT DÉJÀ (dans AWS, ou ailleurs)
# pour les réutiliser ailleurs dans le code.
# ─────────────────────────────────────────────────────────────────

# Récupère le certificat TLS du fournisseur OIDC du cluster EKS
# Ce certificat est nécessaire pour établir une relation de confiance entre AWS IAM et le cluster
data "tls_certificate" "eks-certificate" {
  # URL de l'émetteur OIDC du cluster EKS — construite dynamiquement depuis la ressource EKS créée
  # Décomposition :
  #   aws_eks_cluster.eks[0]      → le cluster EKS (index [0] car créé avec count)
  #   .identity[0]                → bloc "identity" du cluster (contient les infos OIDC)
  #   .oidc[0]                    → bloc "oidc" dans identity
  #   .issuer                     → l'URL de l'émetteur OIDC, ex: "https://oidc.eks.eu-west-1.amazonaws.com/id/XXXX"
  # Ce certificat permet à AWS de vérifier que les tokens JWT viennent bien de ce cluster
  url = aws_eks_cluster.eks[0].identity[0].oidc[0].issuer
}

# ─────────────────────────────────────────────────────────────────
# Génère le document de politique IAM pour l'OIDC (en mémoire, pas dans AWS)
# Ce document définit QUI peut endosser le rôle OIDC et DANS QUELLES CONDITIONS
# Il est référencé dans iam.tf via : data.aws_iam_policy_document.eks_oidc_assume_role_policy.json
# ─────────────────────────────────────────────────────────────────
data "aws_iam_policy_document" "eks_oidc_assume_role_policy" {

  # Un "statement" = une règle dans la politique IAM
  statement {
    # L'action autorisée : "AssumeRoleWithWebIdentity" = endosser un rôle via un token OIDC (JWT)
    # C'est différent de "AssumeRole" classique — ici l'identité vient d'un fournisseur externe (le cluster)
    actions = ["sts:AssumeRoleWithWebIdentity"]

    # Cette règle est permissive (Allow) — elle autorise l'action ci-dessus
    effect = "Allow"

    # Condition : la règle ne s'applique QUE SI cette condition est vraie
    condition {
      # "StringEquals" = comparaison exacte de chaîne de caractères (sensible à la casse)
      test = "StringEquals"

      # La variable à tester : l'URL de l'OIDC provider SANS le préfixe "https://" + ":sub"
      # "sub" (subject) est le champ dans le token JWT qui identifie le Service Account Kubernetes
      # replace(...) supprime "https://" de l'URL pour obtenir juste le nom de domaine
      # Résultat attendu : "oidc.eks.eu-west-1.amazonaws.com/id/XXXX:sub"
      variable = "${replace(aws_iam_openid_connect_provider.eks-oidc.url, "https://", "")}:sub"

      # Valeur attendue du "sub" : le Service Account Kubernetes autorisé à endosser ce rôle
      # Format : "system:serviceaccount:<namespace>:<nom-du-service-account>"
      # Ici : le service account "aws-test" dans le namespace "default"
      # Seul ce pod précis pourra utiliser le rôle IAM OIDC
      values = ["system:serviceaccount:default:aws-test"]
    }

    # Le "principal" = l'entité qui est autorisée à endosser le rôle
    principals {
      # L'ARN du fournisseur OIDC créé dans AWS IAM (ressource définie dans eks.tf ou oidc.tf)
      # ex: "arn:aws:iam::123456789012:oidc-provider/oidc.eks.eu-west-1.amazonaws.com/id/XXXX"
      identifiers = [aws_iam_openid_connect_provider.eks-oidc.arn]

      # "Federated" = le principal est un fournisseur d'identité externe (OIDC, SAML...)
      # et non un utilisateur ou service AWS natif
      type = "Federated"
    }
  }
}
