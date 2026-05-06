# terraform
alias tf='terraform'                            # Command terraform
alias tfa='terraform apply'                     # Apply current configuration
alias tfc='terraform console'                   # Console
alias tff='terraform fmt'                       # fmt
alias tffr='terraform fmt --recursive'          # fmt recursively
alias tfg='terraform graph'                     # Graph
alias tfo='terraform output'                    # Output
alias tfim='terraform import'                   # Import
alias tfin='terraform init'                     # initialize
alias tfval='terraform validate'                # Validate config
alias tfwl='terraform workspace list'           # List all workspace
alias tfws='terraform workspace select'         # Select a workspace
alias tfwn='terraform workspace new'            # Create a new workspace


# Terraform alias

alias tfV='terraform --version'

alias tfid='terraform init -get=true -reconfigure -upgrade=true -backend-config=dev/backend.tfvars'
alias tfpd='terraform plan -var-file=dev/terraform.tfvars'
alias tfad='terraform apply -var-file=dev/terraform.tfvars'
alias tfdd='terraform destroy -var-file=dev/terraform.tfvars'

alias tfiqa='terraform init -get=true -reconfigure -upgrade=true -backend-config=qa/backend.tfvars'
alias tfpqa='terraform plan -var-file=qa/terraform.tfvars'
alias tfaqa='terraform apply -var-file=qa/terraform.tfvars'

alias tfip='terraform init -get=true -reconfigure -upgrade=true -backend-config=prod/backend.tfvars'
alias tfpp='terraform plan -var-file=prod/terraform.tfvars'
alias tfap='terraform apply -var-file=prod/terraform.tfvars'
alias tfdp='terraform destroy -var-file=prod/terraform.tfvars'







