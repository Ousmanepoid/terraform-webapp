#!/bin/sh

# Script to run terraform modules
# Usage :
# - ./script.sh


# Stop script if missing dependency
required_commands="terraform"
for command in $required_commands; do
	if [ -z "$(command -v $command)" ]; then
		echo "error: required command not found: \e[91m$command\e[97m"
        exit 1
	fi
done


# Get value of a variable declared in a given file from this pattern: variable = "value"
# Usage: get_var_value <file> <variable>
get_var_value() {
    local file=$1
    local variable=$2

    cat $file | grep '=' | grep -w $variable | sed '/.*#.*/d' | sed 's|.*=.*"\(.*\)".*|\1|' | head -n 1
}

cloud_provider="$(get_var_value terraform.tfvars cloud_provider)"
cluster_name="$(get_var_value terraform.tfvars cluster_name)"
tenant_name="$(get_var_value terraform.tfvars tenant)"
webapp_name="$(get_var_value terraform.tfvars webapp_name)"
state_file_name="tfstate-$cluster_name-tenant-$tenant_name-webapp-$webapp_name"

# Generate state_storage_name for Azure backend
# Azure storage account names must be 3-24 chars, lowercase alphanumeric only
azure_subscription_id="$(get_var_value terraform.tfvars azure_subscription_id)"
sub_hash="$(echo -n "$azure_subscription_id" | sha256sum | cut -c1-9)"
state_storage_name="csmstates${sub_hash}"



# Clear old data
rm -rf .terraform*
rm -rf terraform.tfstate*


# Automatically detect all the $TEMPLATE variables from a given a file,
# and replace them with the value that the same variable has in the current script.
# Usage: prepare_target_file <source file> <target file>
prepare_target_file() {
  local source_file=$1
  local target_file=$2

  rm -f $target_file
  cp -f $source_file $target_file

  local needed_variables="$(cat $target_file | grep TEMPLATE_ | sed 's|.*TEMPLATE_\([a-zA-Z_]*\).*|\1|' | sort -u)"
  for var in $needed_variables; do

    # Declare the TEMPLATE_variable
    eval value=\$$var

    # Replace TEMPLATE with the actual value
    sed -i "s|\$TEMPLATE_$var|$value|" $target_file
  done
}
target_file='target.tf'


# The trick here is to write configuration in a dynamic file created at the begin of the
# execution, containing the config that the concerned provider is waiting for Terraform backend.
# Then, Terraform will automatically detects it from its .tf extension.
case "$(echo $cloud_provider)" in
  'azure')
    prepare_target_file "targets/$cloud_provider.target.tf" $target_file
    ;;

  'kob')
    state_url="$(get_var_value terraform.tfvars state_host)/$state_file_name"

    if [ -z $TF_HTTP_USERNAME ] || [ -z $TF_HTTP_PASSWORD ]; then
        echo "error: empty TF_HTTP_USERNAME or TF_HTTP_PASSWORD (required for backend authentication)"
        echo "  export TF_HTTP_USERNAME="
        echo "  export TF_HTTP_PASSWORD="
        exit
    else
        echo "found TF_HTTP_USERNAME & TF_HTTP_PASSWORD"
    fi

    export TF_CLI_ARGS_apply="-lock=false"

    prepare_target_file "targets/$cloud_provider.target.tf" $target_file
    ;;

  *)
    echo "error: unknown or empty \e[91mcloud_provider\e[0m from terraform.tfvars"
    exit
    ;;
esac


# Deploy
terraform fmt $target_file
terraform init -upgrade -reconfigure
terraform plan -out .terraform.plan
terraform apply .terraform.plan

exit