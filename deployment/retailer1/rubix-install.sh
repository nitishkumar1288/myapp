#!/bin/bash
#DIR="$(dirname "${BASH_SOURCE[0]}")"
echo ":::::::::::::: START SCRIPT :::::::::::::::::"
#cd /opt/atlassian/pipelines/agent/build/
echo "Finding all files under directory first........"


search_dir=$CI_PROJECT_DIR/artifacts
  for entry in "$search_dir"/*
do
  echo "$entry"
done


#$unzip -q -c /opt/atlassian/pipelines/agent/build/target/rubix-plugin-aldo-0.0.4.jar META-INF/MANIFEST.MF


# ######################
# FUNCTION DEFINITIONS
# ######################
function abort_on_failure () {
 if [[ ${1} ]];then
 echo "${1}. Aborting."
 fi
exit 1
}
function get_token () {
 echo "${!apiHost}/oauth/token?username=${!retailerUserName}&password=${!retailerPassWord}&scope=api&client_id=${!accountId}&client_secret=${!clientSecret}&grant_type=password"
token=$(\
  curl -s -XPOST \
  -H "Cache-Control: no-cache" \
  -H "fluent.account: ${ACCOUNT}" \
  "${!apiHost}/oauth/token?username=${!retailerUserName}&password=${!retailerPassWord}&scope=api&client_id=${!accountId}&client_secret=${!clientSecret}&grant_type=password" \
      | jq ".access_token")
token=$(sed -e 's/^"//' -e 's/"$//' <<<"$token")
case $token in null)
 abort_on_failure "Failed to obtain the access token"
 ;;
esac
if [ -z "$token" ]
then
 abort_on_failure "Zero length : Failed to obtain the access
token"
 exit 1
fi
}



function updatemanifest() {
 echo "Updating Manifest............................"
 if [[ ${1} && ${2} ]];then
 echo "projectName: '${1}', version: '${2}'"
 else
 echo "$1 or $2 is not set";
 abort_on_failure "$1 or $2 is not set"
 fi
#Update Bundle-SymbolicName in the MANIFEST.MF file
echo "Bundle-SymbolicName: ${!accountId}.${!pluginNameSpace}" > updatemanifest.txt
#UPDATE MANIFEST COMMAND
jar -umf updatemanifest.txt /opt/atlassian/pipelines/agent/build/artifacts/"${projectName}"-"${version}".jar
rm updatemanifest.txt
}

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

function check-service-running()
{
 service_url=$1
 count=0
 max=1
 until [ $count -gt $max ] || $(curl --output /dev/null --silent --head --
fail "${service_url}"); do
 sleep 10
 count=$((count+1))
 done
 if [ $count -gt $max ]
 then
 abort_on_failure "Error! No response from ${service_url}."
 fi
}

function replace() {
    templateFile=${1}
    variablesFile=${2}
    output=`cat ${templateFile}`
    for row in $(jq -r '.replace_values | to_entries|map("\(.key)|\(.value|tostring)")|.[] | @base64' ${variablesFile}); do
        row=`echo ${row} | base64 --decode`
    	IFS='|' read key value <<< "$row"
        key="{{${key}}}"
    	output=$(sed -e "s~${key}~${value}~g" <<< "$output")
    done
    echo $output
}

function replace_retailer() {
    templateFile=${1}
    variablesFile=${2}
    output=`cat ${templateFile}.json`
    for row in $(jq -r --arg v1 "$retailerName" '.retailers[] | select(.[$v1])[] | .replace_values | to_entries|map("\(.key)|\(.value|tostring)")|.[] | @base64' ${variablesFile}); do
        row=`echo ${row} | base64 --decode`
    	IFS='|' read key value <<< "$row"
        key="{{${key}}}"
    	output=$(sed -e "s~${key}~${value}~g" <<< "$output")
    done
    echo $output
}

function contains() {
    local n=$#
    local value=${!n}
    for ((i=1;i < $#;i++)) {
        if [ "${!i}" == "${value}" ]; then
            echo "y"
            return 0
        fi
    }
    echo "n"
    return 1
}


# ######################
# EXECUTION
# ######################

# ######################
# Step 1) Fetch all the environmental variables specific to branch
# ######################

workflow_path="./deployment/retailer1/workflows/"
retailerName="retailer"

if [ $CI_COMMIT_REF_NAME == "dev" ]
then
  environmentalVariablePrefix="DEV"
  variablesFile="./deployment/retailer1/covetrus_dev_ret_1_var.json"
elif [ $CI_COMMIT_REF_NAME == "qa" ]
then
  environmentalVariablePrefix="QA"
  variablesFile="./deployment/retailer1/covetrus_qa_ret_1_var.json"
elif [ $CI_COMMIT_REF_NAME == "stage" ]
then
  environmentalVariablePrefix="STAGE"
  variablesFile="./deployment/retailer1/covetrus_stage_ret_1_var.json"
elif [ $CI_COMMIT_REF_NAME == "prod" ]
then
  environmentalVariablePrefix="PROD"
  variablesFile="./deployment/retailer1/covetrus_prod_ret_1_var.json"
else
  echo "None of the branch condition is matching so exiting the process"
  exit 1
fi

accountId=${environmentalVariablePrefix}"_ACCOUNT"
apiHost=${environmentalVariablePrefix}"_API_HOST"
clientSecret=${environmentalVariablePrefix}"_CLIENT_SECRET"
pluginNameSpace=${environmentalVariablePrefix}"_PLUGIN_NAMESPACE"
retailerUserName=${environmentalVariablePrefix}"_RETAILER_USERNAME"
retailerPassWord=${environmentalVariablePrefix}"_RETAILER_PASSWORD"

require_environment_variable ${accountId}
require_environment_variable ${apiHost}
require_environment_variable ${clientSecret}
require_environment_variable ${pluginNameSpace}
require_environment_variable ${retailerUserName}
require_environment_variable ${retailerPassWord}


echo "accountId=${!accountId},apiHost=${!apiHost},clientSecret=${!clientSecret},pluginNameSpace=${!pluginNameSpace},retailerUserName=${!retailerUserName},retailerPassWord=${!retailerPassWord}"


# ######################
# Step 2) Get global user information
# ######################


require_environment_variable 'GLOBAL_GIT_USER_NAME'
require_environment_variable 'GLOBAL_GIT_EMAIL_ID'
require_environment_variable 'GLOBAL_GIT_ACCESS_TOKEN'

echo "GLOBAL_GIT_USER_NAME=${GLOBAL_GIT_USER_NAME}, GLOBAL_GIT_EMAIL_ID=${GLOBAL_GIT_EMAIL_ID},GLOBAL_GIT_ACCESS_TOKEN=${GLOBAL_GIT_ACCESS_TOKEN}"


# ######################
# Step 3) Get the access token
# ######################


#check-service-running "${!apiHost}"/orchestration/rest/health

echo "Getting token for account ${!accountId}"
get_token
echo "Got token for account ${!accountId}"
#check-service-running "${!apiHost}"/api/metrics/healthcheck


# ######################
# Step 4) Uploading the plugin
# ######################

# Retrieve project version and name
echo "Getting version and project name for account ${!accountId}"
version=$(mvn -q -Dexec.executable='echo' -Dexec.args='${project.version}' --non-recursive exec:exec)
projectName=$(mvn -q -Dexec.executable='echo' -Dexec.args='${project.artifactId}' --non-recursive exec:exec)

#echo "Updating manifest file for ${projectName}-${version}.jar"
#updatemanifest "$projectName" "$version"
echo "Manifest update skipped"


# Upload plugin
echo "Uploading plugin ${projectName}-${version}.jar to account ${!accountId} with namespace ${!pluginNameSpace}"

response=$( \
  curl -s -o /dev/null -w "%{http_code}" -XPOST "${!apiHost}/orchestration/rest/v1/plugin/upload" \
  -H "content-type: multipart/form-data" \
  -H "Authorization: bearer ${token}" \
  -H "Connection: keep-alive" \
  -H 'Cache-Control: no-cache' \
  -H "fluent.account: ${!accountId}" \
  -F "file=@artifacts/${projectName}-${version}.jar"
)
if [[ ${response} -ne 200 ]]
then
 abort_on_failure "Plugin Jar upload failed"
fi

# ######################
# Step 5) Installing the plugin
# ######################

echo "Installing plugin ${projectName}-${version} to account ${!accountId} with namespace ${!pluginNameSpace}"
response=$( \
 curl -s -o /dev/null -w "%{http_code}" -XPOST "${!apiHost}/orchestration/rest/v1/plugin/install" \
 -H "Content-Type: application/json" \
 -H "Authorization: Bearer ${token}" \
 -H "Cache-Control: no-cache" \
 -H "fluent.account: ${!accountId}" \
 -d "{\"accountId\":\"${!accountId}\",\"bundleName\" :\"${!accountId}.${!pluginNameSpace}::${version}\"}"
)
echo "${response}"
if [[ ${response} -ne 200 ]]
then
 abort_on_failure "Plugin Jar install failed"
fi
echo "Plugin Install is Success With Code :: $response"

echo "Sleeping for 10 seconds.........."
sleep 10


# ######################
# Step 6) Verify plugin status
# ######################

resp=$( \
 curl -s -XGET \
 "${!apiHost}/orchestration/rest/v1/plugin/${!accountId}.${!pluginNameSpace}::${version}/status" \
 -H "Authorization: Bearer ${token}" \
 -H "Cache-Control: no-cache" \
 | jq ".bundleVersion"
)
echo "Bundle Version :> $resp"

stat=$( \
 curl -s -XGET \
 "${!apiHost}/orchestration/rest/v1/plugin/${!accountId}.${!pluginNameSpace}::${version}/status" \
 -H "Authorization: Bearer ${token}" \
 -H "Cache-Control: no-cache" \
 | jq ".bundleStatus"
)
echo "Bundle Status :> $stat"
desiredstatus="ACTIVE"
echo "Desired status :> $desiredstatus"
if [[ "${stat}" == "$desiredstatus" ]]
then
  abort_on_failure "Current Version Not ACTIVE"
fi

echo "Deployment Success"


# ######################
# Step 7) Updating jar version in POM
# ######################
currentVersion="$(mvn -q -Dexec.executable=echo -Dexec.args='${project.version}' --non-recursive exec:exec)"
majorVersion=${currentVersion%.*}
echo "majorVersion:: $majorVersion"
minorVersion=${currentVersion##*.}
echo "minorVersion:: $minorVersion"
let newMinorVersion=minorVersion+1
newVersion="${majorVersion}.${newMinorVersion}"
echo "newVersion:: $newVersion"
mvn versions:set -DnewVersion=${newVersion} -f pom.xml

#Updating the POM.xml file version
echo "CI_COMMIT_REF_NAME:: $CI_COMMIT_REF_NAME"
git config --global user.name $GLOBAL_GIT_USER_NAME
git config --global user.email $GLOBAL_GIT_EMAIL_ID
git checkout -b $CI_COMMIT_REF_NAME
git add pom.xml
git commit -m '[skip ci] Upversion build'
git remote set-url origin https://$GLOBAL_GIT_USER_NAME:$GLOBAL_GIT_ACCESS_TOKEN@gitlab.com/GreatPetRx/oms-fluent.git
git push --set-upstream origin $CI_COMMIT_REF_NAME


# ######################
# Step 8) Initiate the workflow update
# ######################
echo "Using variables file: $variablesFile"
echo "Using retailer name: $retailerName"

retailerId=$(jq -r --arg v1 "${retailerName}" '.retailers[] | select(has($v1)) | .[].retailer_id' ${variablesFile})

echo "apiHost=${!apiHost}, accountId=${!accountId}, clientSecret=${!clientSecret}, retailerId:${retailerId}, retailerUserName:${!retailerUserName}, retailerPassWord:${!retailerPassWord} "
get_token
echo "Got token"

workflowTemplates=(
"BILLING_ACCOUNT_CUSTOMER:BILLING_ACCOUNT::CUSTOMER"
"CONTROL_GROUP_BASE:CONTROL_GROUP::BASE"
"CONTROL_GROUP_ATS:CONTROL_GROUP::ATS"
"INVENTORY_CATALOGUE_DEFAULT:INVENTORY_CATALOGUE::DEFAULT"
"LOCATION_WAREHOUSE:LOCATION::WAREHOUSE"
"ORDER_HD:ORDER::HD"
"PRODUCT_CATALOGUE_MASTER:PRODUCT_CATALOGUE::MASTER"
"RETURN_ORDER_DEFAULT:RETURN_ORDER::DEFAULT"
"VIRTUAL_CATALOGUE_ATS:VIRTUAL_CATALOGUE::ATS"
"VIRTUAL_CATALOGUE_BASE:VIRTUAL_CATALOGUE::BASE"
)

for workflowTemplate in "${workflowTemplates[@]}"
do
	workflowKey=${workflowTemplate%%:*}
	workflowValue=${workflowTemplate#*:}

	echo "****************************************************************************************"

	echo "workflowKey : ${workflowKey}"
	echo "workflowValue : ${workflowValue}"


	workflowTemplatePath=${workflow_path}$workflowKey
	echo "workflowTemplatePath:${workflowTemplatePath}"

  echo "Generating workflow from template file:'${workflowTemplate}' and variables file:'${variablesFile}' for account:${!accountId}, retailerId:${retailerId}"
  workflow=$(replace_retailer ${workflowTemplatePath} ${variablesFile})

  currentWorkflow=$( \
      curl -s -X GET \
      -H "Content-Type: application/json" \
      -H "Authorization: Bearer ${token}" \
      -H "fluent.account: ${!accountId}" \
      -H "Content-Type: application/json" \
      -H "Cache-Control: no-cache" \
      "${!apiHost}/api/v4.1/workflow/${retailerId}/${workflowValue}"
  )

  currentWorkflowVersion=$(jq '.version' <<< ${currentWorkflow})
  currentWorkflowVersion=$(sed -e 's/^"//' -e 's/"$//' <<<"$currentWorkflowVersion")
  if [ -z $currentWorkflowVersion ];
  then
      currentWorkflowVersion="1.0"
  fi
  echo "Current workflow version: '${currentWorkflowVersion}'"

  #workflow=$(sed -e "s~{{workflow_version}}~${currentWorkflowVersion}~g" <<< "$workflow")

  currentWorkflowRulesets=$(jq '.rulesets' <<< ${currentWorkflow})
  workflowRuleSets=$(jq '.rulesets' <<< ${workflow})


  echo "${workflowRuleSets//[[:blank:]]/}" > ${workflow_path}"tempRepoRulesets.json"
  echo "${currentWorkflowRulesets//[[:blank:]]/}" > ${workflow_path}"tempCurrentRulesets.json"

  if diff <(jq --sort-keys . ${workflow_path}"tempRepoRulesets.json") <(jq --sort-keys . ${workflow_path}"tempCurrentRulesets.json") ;then
    echo "Workflow rule sets are same and hence update is skipped"
  else
    echo "Workflow rule sets are different"
    #workflow=$(sed -e "s~{{workflow_version}}~${currentWorkflowVersion}~g" <<< "$workflow")
    echo $workflow > ${workflow_path}"tempWorkflow.json"

    filepath=${workflow_path}"tempWorkflow.json"
    echo "filepath:${filepath}"


    response=$( \
        curl -s -X PUT \
        -H "Content-Type: application/json" \
        -H "Authorization: Bearer ${token}" \
        -H "fluent.account: ${!accountId}" \
        -H "Cache-Control: no-cache" \
        -o response.txt \
        -w "%{http_code}" \
        -d "@${filepath}" ${!apiHost}/api/v4.1/workflow
      )

      cat response.txt

      if [ $response != "200" ]; then
        echo "Failure: error code: ${response}"
        exit 1
      else
        echo "Workflow Upload Success: ${response}"
      fi
  fi

	echo "****************************************************************************************"
	printf "\n \n"
done
