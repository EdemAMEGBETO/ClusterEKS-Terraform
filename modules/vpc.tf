# Bloc "locals" : permet de définir des variables locales réutilisables dans ce fichier uniquement
locals {
  # On récupère la valeur de la variable "cluster-name" pour l'utiliser plus facilement via local.cluster-name
  cluster-name = var.cluster-name
}

# Création du VPC (Virtual Private Cloud) : le réseau privé isolé dans AWS qui contiendra toutes nos ressources
resource "aws_vpc" "vpc" {
  # Plage d'adresses IP du VPC, ex: "10.0.0.0/16" — définie dans les variables pour être configurable
  cidr_block = var.cidr-block

  # "default" signifie que les instances EC2 dans ce VPC ne sont pas sur du hardware dédié (option la moins coûteuse)
  instance_tenancy = "default"

  # Permet aux instances du VPC d'avoir des noms DNS publics (ex: ec2-xx.compute.amazonaws.com)
  enable_dns_hostnames = true

  # Active la résolution DNS à l'intérieur du VPC — nécessaire pour que les services se trouvent par nom
  enable_dns_support = true

  tags = {
    # Tag "Name" : nom affiché dans la console AWS pour identifier ce VPC
    Name = var.vpc-name
    # Tag "Env" : indique l'environnement (dev, staging, prod...) — utile pour filtrer les ressources
    Env = var.env
  }
}

# Création de l'Internet Gateway (IGW) : la "porte d'entrée/sortie" vers Internet pour le VPC
resource "aws_internet_gateway" "igw" {
  # Associe cette IGW au VPC qu'on vient de créer, via son ID
  vpc_id = aws_vpc.vpc.id

  tags = {
    # Nom affiché dans la console AWS
    Name = var.igw-name
    # Environnement
    env = var.env
    # Tag requis par Kubernetes/EKS pour savoir que cette IGW appartient au cluster
    "kubernetes.io/cluster/${local.cluster-name}" = "owned"
  }

  # Indique à Terraform de créer le VPC AVANT cette IGW (dépendance explicite)
  depends_on = [aws_vpc.vpc]
}

# Création des sous-réseaux PUBLICS (accessibles depuis Internet via l'IGW)
resource "aws_subnet" "public-subnet" {
  # "count" permet de créer plusieurs sous-réseaux en une seule ressource — le nombre vient d'une variable
  count = var.pub-subnet-count

  # Chaque sous-réseau est créé dans le même VPC
  vpc_id = aws_vpc.vpc.id

  # "element(..., count.index)" sélectionne le CIDR correspondant à l'index courant dans la liste
  # ex: index 0 → "10.0.1.0/24", index 1 → "10.0.2.0/24", etc.
  cidr_block = element(var.pub-cidr-block, count.index)

  # Chaque sous-réseau est placé dans une Availability Zone différente pour la haute disponibilité
  availability_zone = element(var.pub-availability-zone, count.index)

  # "true" : toute instance lancée dans ce sous-réseau reçoit automatiquement une IP publique
  map_public_ip_on_launch = true

  tags = {
    # Nom dynamique : "public-subnet-1", "public-subnet-2", etc. (count.index commence à 0, +1 pour lisibilité)
    Name = "${var.pub-sub-name}-${count.index + 1}"
    Env  = var.env
    # Tag requis par EKS pour identifier les sous-réseaux appartenant au cluster
    "kubernetes.io/cluster/${local.cluster-name}" = "owned"
    # Tag requis pour qu'AWS Load Balancer Controller crée des Load Balancers publics (ELB) dans ces subnets
    "kubernetes.io/role/elb" = "1"
  }

  # Ces sous-réseaux ne peuvent être créés qu'après le VPC
  depends_on = [aws_vpc.vpc]
}

# Création des sous-réseaux PRIVÉS (pas d'accès direct depuis Internet — accès sortant via NAT Gateway)
resource "aws_subnet" "private-subnet" {
  # Nombre de sous-réseaux privés à créer
  count = var.pri-subnet-count

  vpc_id = aws_vpc.vpc.id

  # Plage IP privée pour chaque sous-réseau (ex: "10.0.10.0/24", "10.0.11.0/24"...)
  cidr_block = element(var.pri-cidr-block, count.index)

  # Répartition sur plusieurs Availability Zones pour la résilience
  availability_zone = element(var.pri-availability-zone, count.index)

  # "false" : les instances dans ce sous-réseau n'ont PAS d'IP publique — elles sont inaccessibles depuis Internet
  map_public_ip_on_launch = false

  tags = {
    # Nom dynamique : "private-subnet-1", "private-subnet-2", etc.
    Name = "${var.pri-sub-name}-${count.index + 1}"
    Env  = var.env
    # Tag requis par EKS pour identifier les sous-réseaux du cluster
    "kubernetes.io/cluster/${local.cluster-name}" = "owned"
    # Tag requis pour qu'AWS Load Balancer Controller crée des Load Balancers INTERNES dans ces subnets
    "kubernetes.io/role/internal-elb" = "1"
  }

  depends_on = [aws_vpc.vpc]
}

# Création de la table de routage PUBLIQUE : définit comment le trafic des sous-réseaux publics est routé
resource "aws_route_table" "public-rt" {
  # Associée au VPC principal
  vpc_id = aws_vpc.vpc.id

  # Règle de routage : tout le trafic (0.0.0.0/0 = toutes destinations) sort via l'Internet Gateway
  route {
    cidr_block = "0.0.0.0/0"      # "toutes les adresses IP"
    gateway_id = aws_internet_gateway.igw.id  # → passe par l'IGW pour aller sur Internet
  }

  tags = {
    Name = var.public-rt-name
    env  = var.env
  }

  depends_on = [aws_vpc.vpc]
}

# Association de la table de routage publique à chaque sous-réseau public
resource "aws_route_table_association" "name" {
  # On associe à 3 sous-réseaux publics (count de 0 à 2)
  count = 3

  # La table de routage à associer
  route_table_id = aws_route_table.public-rt.id

  # Le sous-réseau correspondant à l'index courant
  subnet_id = aws_subnet.public-subnet[count.index].id

  depends_on = [
    aws_vpc.vpc,
    aws_subnet.public-subnet,
  ]
}

# Création d'une Elastic IP (EIP) : adresse IP publique fixe qui sera attribuée au NAT Gateway
resource "aws_eip" "ngw-eip" {
  # "vpc" indique que cette IP est destinée à être utilisée dans un VPC (et non EC2-Classic, obsolète)
  domain = "vpc"

  tags = {
    Name = var.eip-name
  }

  depends_on = [aws_vpc.vpc]
}

# Création du NAT Gateway : permet aux ressources PRIVÉES d'accéder à Internet en sortie (sans exposer d'IP publique)
resource "aws_nat_gateway" "ngw" {
  # L'IP publique fixe (EIP) que le NAT Gateway utilisera pour communiquer avec Internet
  allocation_id = aws_eip.ngw-eip.id

  # Le NAT Gateway est placé dans le PREMIER sous-réseau PUBLIC (index 0) — il doit être dans un subnet public
  subnet_id = aws_subnet.public-subnet[0].id

  tags = {
    Name = var.ngw-name
  }

  # Le NAT Gateway nécessite le VPC et l'EIP pour être créé
  depends_on = [
    aws_vpc.vpc,
    aws_eip.ngw-eip,
  ]
}

# Création de la table de routage PRIVÉE : le trafic sortant des subnets privés passe par le NAT Gateway
resource "aws_route_table" "private-rt" {
  vpc_id = aws_vpc.vpc.id

  # Règle de routage : tout le trafic sortant des subnets privés passe par le NAT Gateway
  route {
    cidr_block     = "0.0.0.0/0"              # toutes destinations
    nat_gateway_id = aws_nat_gateway.ngw.id   # → passe par le NAT Gateway (et non l'IGW)
  }

  tags = {
    Name = var.private-rt-name
    env  = var.env
  }

  depends_on = [aws_vpc.vpc]
}

# Association de la table de routage privée à chaque sous-réseau privé
resource "aws_route_table_association" "private-rt-association" {
  # On associe à 3 sous-réseaux privés
  count = 3

  route_table_id = aws_route_table.private-rt.id

  # Le sous-réseau privé correspondant à l'index courant
  subnet_id = aws_subnet.private-subnet[count.index].id

  depends_on = [
    aws_vpc.vpc,
    aws_subnet.private-subnet,
  ]
}

# Création du Security Group pour le cluster EKS : définit les règles de trafic réseau autorisé
resource "aws_security_group" "eks-cluster-sg" {
  # Nom du security group (visible dans la console AWS)
  name = var.eks-sg

  # Description humaine de l'usage du security group
  description = "Allow 443 from Jump Server only"

  # Associé au VPC principal
  vpc_id = aws_vpc.vpc.id

  # Règle ENTRANTE (ingress) : autorise le trafic HTTPS (port 443) entrant
  ingress {
    from_port   = 443          # port de début de la plage autorisée
    to_port     = 443          # port de fin (même port → uniquement le 443)
    protocol    = "tcp"        # protocole TCP (HTTPS utilise TCP)
    cidr_blocks = ["0.0.0.0/0"] # autorise depuis toutes les IPs — À RESTREINDRE en production à l'IP du Jump Server
  }

  # Règle SORTANTE (egress) : autorise TOUT le trafic sortant (pratique courante pour les clusters)
  egress {
    from_port   = 0            # port 0 = tous les ports
    to_port     = 0            # port 0 = tous les ports
    protocol    = "-1"         # "-1" = tous les protocoles
    cidr_blocks = ["0.0.0.0/0"] # vers toutes les destinations
  }

  tags = {
    Name = var.eks-sg
  }
}
