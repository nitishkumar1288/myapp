#!/bin/bash
#DIR="$(dirname "${BASH_SOURCE[0]}")"
echo ":::::::::::::: START SCRIPT :::::::::::::::::"
#cd /opt/atlassian/pipelines/agent/build/
echo "Finding all files under directory first........"


function require_environment_variable() {
 required_var_name="$1";
 required_var_value=${!required_var_name}
 if [[ $required_var_value ]];
 then
 echo "Success - Found $required_var_name in environment variables..."
 else
 abort_on_failure "Failure - $required_var_name environment variable not
set. Please set this environment variable and try again."
 fi;
}

accountId="DEVACCOUNT"
require_environment_variable ${accountId}

echo "checkaccountId=${!accountId}"
